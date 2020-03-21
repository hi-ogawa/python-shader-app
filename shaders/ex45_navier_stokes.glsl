//
// Navier Stokes equation
//
//
// Data format is
//   buf_a:
//     xy: velocity
//     z:  density
//     w:  curl(velocity)
//   buf_b:
//     xyz: color
//
// In the code, variable name convention is
//   velocity (u)
//   density  (q)
//   color    (c)
//   position (r)
//
// TODO:
// - prettier initial source
// - visualization
//   - velocity
//     - fast decay advectable source on grid point?
//     - div, curl, etc..
// - stability analysis
// - solve analytically tractable boundary/initial value and compare with analytical result
//
// Reference
// - Chimera's Breath by nimitz https://www.shadertoy.com/view/4tGfDW
// - Simple and Fast Fluids (Martin Guay, Fabrice Colin, Richard Egli)
// - Vorticity confinement https://en.wikipedia.org/wiki/Vorticity_confinement
//

/*
%%config-start%%
samplers:
  - name: buf_a
    type: framebuffer
    size: $default
    mipmap: false
    wrap: repeat
    filter: linear
    internal_format: GL_RGBA32F

  - name: buf_b
    type: framebuffer
    size: $default
    mipmap: false
    wrap: repeat
    filter: linear
    internal_format: GL_RGBA32F

programs:
  - name: mainImage1
    samplers: [buf_a]
    output: buf_a
    substep: true

  - name: mainImage2
    samplers: [buf_a, buf_b]
    output: buf_b
    substep: true

  - name: mainImage
    samplers: [buf_a, buf_b]
    output: $default

substep:
  num_iter: 4
  schedule:
    - type: program
      name: mainImage1
    - type: sampler
      name: buf_a
    - type: program
      name: mainImage2
    - type: sampler
      name: buf_b

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

#include "common_v0.glsl"

//
// Utilities
//

const vec2 XX = vec2(1.0, 0.0);
const vec2 YY = vec2(0.0, 1.0);

float dot2(float v) { return dot(v, v); }
float dot2(vec2  v) { return dot(v, v); }
float reduceMax(vec2 v) { return max(v[0], v[1]); }

vec4 read(sampler2D buf, vec2 p) {
  return textureLod(buf, p / iResolution.xy, 0.0);
}


//
// Display
//

void mainImage(out vec4 frag_color, in vec2 frag_coord, sampler2D buf_a, sampler2D buf_b){
  vec3 color = read(buf_b, frag_coord).xyz;

  {
    // visualize velocity and density
    vec4 CC = read(buf_a, frag_coord);

    vec2 u = CC.xy;
    float q = CC.z;
    float curl_u = CC.w;
    const float kScaleU = 1.0;
    const float kScaleQ = 3.0;
    const float kScaleCurlU = 0.05;

    // [debug] density
    // color = vec3(q / kScaleQ);

    // [debug] velocity
    // color = vec3(u, 0.0) / kScaleU + 0.5;

    // [debug] vorticity
    // color = vec3(max(0.0, curl_u), max(0.0, -curl_u), 0.0) / kScaleCurlU;
  }

  frag_color = vec4(color, 1.0);
}


//
// PDE numerically
//

const float dt = 0.15; // dx = 1.0 as pixel spacing itself
const float k  = 0.5;  // pressure-density relation p = kq
const float mu = 0.5;  // viscosity
const float e  = 0.5;  // vorticity boost factor

vec4 solve1(sampler2D buf_a, vec2 r, vec2 ext_force) {
  vec4 CC = read(buf_a, r);
  vec4 RR = read(buf_a, r + XX);
  vec4 LL = read(buf_a, r - XX);
  vec4 UU = read(buf_a, r + YY);
  vec4 DD = read(buf_a, r - YY);
  vec4 DxF = (RR - LL) / 2.0;
  vec4 DyF = (UU - DD) / 2.0;
  vec4 DxxF = (RR + LL - 2.0 * CC);
  vec4 DyyF = (UU + DD - 2.0 * CC);

  vec2  u = CC.xy;
  float q = CC.z;
  vec2 grad_q = vec2(DxF.z, DyF.z);
  float div_u = DxF.x + DyF.y;
  vec2 lap_u = DxxF.xy + DyyF.xy;
  float curl_u = DxF.y - DyF.x;

  // 1. Mass conservation [q]
  //   Dt(q) + dot(grd(q), u) + q div(u) = 0
  float dq_dt = - dot(grad_q, u) - q * div_u;
  q += dt * dq_dt;

  // 2. Navier-Stokes [u]

  // 2.1. Semi-Lagrangian advection
  u = read(buf_a, r - dt * u).xy;

  // 2.2. Non-advection terms
  vec2 grad_p = k * grad_q;
  vec2 du_dt = vec2(0.0);
  du_dt += (- grad_p + mu * lap_u + ext_force) / q;

  // 3. Vorticity confinement
  vec2 grad_abs_curl_u = vec2(abs(RR.w) - abs(LL.w), abs(UU.w) - abs(DD.w)) / 2.0;
  vec2 vc_n = grad_abs_curl_u / length(grad_abs_curl_u + 1e-7);
  vec2 vc = curl_u * vec2(vc_n.y, - vc_n.x);
  du_dt += e * vc;

  // 4. Adhoc clamp for stability
  u += dt * du_dt;
  u = clamp(u, vec2(-8.0), vec2(8.0));
  q = clamp(q, 0.5, 2.5);

  return vec4(u, q, curl_u);
}


vec3 solve2(sampler2D buf_a, sampler2D buf_b, vec2 r) {
  // Semi-Lagrangian advection
  vec2 u = read(buf_a, r).xy;
  vec3 c = read(buf_b, r - dt * u).xyz;
  return c;
}


float getSource(vec2 frag_coord, vec2 source_coord) {
  float kBumpSize = 32.0; // pixel size
  vec2 r = frag_coord - source_coord;
  // Quandratic bump
  #define INIT(R) max(0.0, 1.0 - dot2(length(R) / kBumpSize))
  float f = INIT(r);
  return f;
}


float getMouseSource(vec2 frag_coord, vec4 _iMouse) {
  bool activated, down;
  vec2 last_click_pos, last_down_pos;
  getMouseState(_iMouse, /*out*/ activated, down, last_click_pos, last_down_pos);
  if (down) {
    return getSource(frag_coord, last_down_pos);
  }
  return 0.0;
}


void mainImage1(out vec4 frag_color, vec2 frag_coord, sampler2D buf_a) {
  // Initialize
  if (iFrame <= 8) {
    float src = getSource(frag_coord, vec2(0.5, 0.5) * iResolution.xy);
    vec2 u = vec2(src) * 4.0;
    float q = 1.0;
    frag_color = vec4(u, q, 0);
    return;
  }

  vec2 ext_force;
  {
    vec2 ext_force_dir = rotate2(2 * M_PI * iTime)[0];
    float ext_force_src = getMouseSource(frag_coord, iMouse) * 0.5;
    ext_force = ext_force_src * ext_force_dir;
  }

  frag_color = solve1(buf_a, frag_coord, ext_force);
}


void mainImage2(out vec4 frag_color, vec2 frag_coord, sampler2D buf_a, sampler2D buf_b) {
  // Initialize
  if (iFrame <= 8) {
    float src = getSource(frag_coord, vec2(0.5, 0.5) * iResolution.xy);
    frag_color.xyz = vec3(src);
    return;
  }

  vec3 c = solve2(buf_a, buf_b, frag_coord);

  float src = getMouseSource(frag_coord, iMouse);
  vec3 c_src = Quick_color(iTime) * src * 0.1;
  c += c_src;

  frag_color.xyz = c;
}
