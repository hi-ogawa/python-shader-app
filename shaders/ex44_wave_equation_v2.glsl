//
// PDE wave equation
//
// TODO: this isn't really working out, compared to fist version ex44_wave_equation.glsl
//
// Transform to coupled 1st order PDE
//   df_dt2 = - 2 eta df_dt + c^2 df_dx2
//   =>
//   g = df_dt
//   h = df_dx
//   dg_dt = - 2 eta g + c^2 dh_dx
//   dh_dt = dg_dx
//
// For 2dim case, we need "h" having two components
//

/*
%%config-start%%
samplers:
  - name: buf
    type: framebuffer
    size: $default
    mipmap: true
    wrap: repeat
    filter: linear
    internal_format: GL_RGBA32F

programs:
  - name: mainImage1
    samplers: [buf]
    output: buf
    substep: true

  - name: mainImage
    samplers: [buf]
    output: $default

substep:
  num_iter: 24
  schedule:
    - type: program
      name: mainImage1
    - type: sampler
      name: buf

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

#include "common_v0.glsl"

// North, East, South, West
const vec2 NN = vec2(+0.0, +1.0);
const vec2 EE = vec2(+1.0, +0.0);

float dot2(float v) { return dot(v, v); }
float dot2(vec2 v)  { return dot(v, v); }
float reduceMax(vec2 v) { return max(v[0], v[1]); }

const float kEncodeScale = 1.0;

// [-k, k] -> [0, 1]
vec4 encode(vec4 fgh) {
  return 0.5 + 0.5 * fgh / kEncodeScale;
}

// [0, 1] -> [-k, k]
vec4 decode(vec4 v) {
  return (2.0 * v - 1.0) * kEncodeScale;
}

const float dt = 0.01;
const float dx = 1.0;
const float c = 3.0;
const float eta = 0.01;

//
// Display
//
void mainImage(out vec4 frag_color, in vec2 frag_coord, sampler2D buf){
  ivec2 texcoord = ivec2(floor(frag_coord));
  vec4 v = texelFetch(buf, texcoord, 0);
  vec3 color = vec3(v.x);
  frag_color = vec4(color, 1.0);
}


//
// PDE numerically
//

vec4 source(vec2 frag_coord, vec2 source_coord) {
  float kBumpSize = 32.0; // pixel size

  vec2 r = frag_coord - source_coord;
  vec4 fgh;


  // Gaussian bump
  // #define INIT(R) exp(- 0.5 * dot2(R / (0.5 * kBumpSize)))

  // Cone
  // #define INIT(R) max(0.0, 1.0 - length(R) / kBumpSize)

  // Quandratic bump
  #define INIT(R) max(0.0, 1.0 - dot2(length(R) / kBumpSize))

  // Rectangle bump
  // f = float(reduceMax(abs(r)) < kBumpSize);

  // Disc bump
  // f = float(length(r) < kBumpSize);

  fgh.x = INIT(r);
  fgh.y = 0;
  fgh.z = (INIT(r + EE) - INIT(r - EE)) / (2 * dx);
  fgh.w = (INIT(r + NN) - INIT(r - NN)) / (2 * dx);
  return fgh;
}

vec4 read(vec2 frag_coord, sampler2D buf) {
  vec2 p = frag_coord / iResolution.xy;
  return decode(texture(buf, p));
}

vec4 getMouseSource(vec2 frag_coord, vec4 mouse) {
  bool activated, down;
  vec2 last_click_pos, last_down_pos;
  getMouseState(mouse, /*out*/ activated, down, last_click_pos, last_down_pos);
  if (down && iFrame % 4 == 0) {
    return source(frag_coord, last_down_pos) * 0.05;
  }
  return vec4(0);
}

void mainImage1(out vec4 frag_color, vec2 frag_coord, sampler2D buf) {
  // Initialization
  if (iFrame <= 1) {
    vec4 fgh = source(frag_coord, vec2(0.5, 0.5) * iResolution.xy);
    frag_color = encode(fgh);
    return;
  }

  // Interaction
  vec4 mouse_fgh = getMouseSource(frag_coord, iMouse);

  vec2 p = frag_coord / iResolution.xy; // in [0, 1]^2
  vec4 fgh   = read(frag_coord, buf);
  vec4 fgh_n = read(frag_coord + NN, buf);
  vec4 fgh_e = read(frag_coord + EE, buf);
  vec4 fgh_s = read(frag_coord - NN, buf);
  vec4 fgh_w = read(frag_coord - EE, buf);

  fgh += mouse_fgh;
  float f  = fgh.x;
  float g  = fgh.y;
  vec2 h = fgh.zw;

  // Explict method for
  //   dg_dt  = - 2 eta g + c^2 div(h)
  //   dh_dt = grad(g)

  vec2 grad_g = vec2(fgh_e.y - fgh_w.y, fgh_n.y - fgh_s.y) / (2 * dx);
  float div_h = ((fgh_e.z - fgh_w.z) + (fgh_n.w - fgh_s.w)) / (2 * dx);

  float dg_dt = - 2 * eta * g + dot2(c) * div_h;
  vec2 dh_dt = grad_g;

  f += dt * g;
  g += dt * dg_dt;
  h += dt * dh_dt;
  frag_color = encode(vec4(f, g, h));
}
