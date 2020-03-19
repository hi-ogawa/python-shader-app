//
// PDE wave equation numerically (Explicit multistep method)
//

/*

[ Derivation ]

∂t^2 f = - 2 mu ∂tf + c^2 ∆f

(f_n+1 + f_n-1 - 2 f_n) / dt^2 = - 2 mu (f_n+1 - f_n-1) / dt + c^2 ∆f_n

(f_n+1 + f_n-1 - 2 f_n) / dt^2 = - mu (f_n+1 - f_n-1) / dt + c^2 ∆f_n

f_n+1 + f_n-1 - 2 f_n = - dt mu (f_n+1 - f_n-1) + dt^2 c^2 ∆f_n

(1 + mu dt) f_n+1 + (1 - mu dt) f_n-1 - 2 f_n = dt^2 c^2 ∆f_n

f_n+1 = (1 / (1 + mu dt)) * (2 f_n - (1 - mu dt) f_n-1 + dt^2 c^2 ∆f_n)

[ NOTE ]
- We keep f_n+1 and f_n in RG channel.
- In each frame, we progree (f_n+1, f_n) -> (f_n+2, f_n)
- "Wall time" velocity [pixel/sec] is derived by "c" = FPS * SUBSTEP_ITER * c * dt
  (e.g. for current config and assuming FPS = 60, it becomes "c" = 60 * 2 * 1 * 0.7 = 84)

[ TODO ]
- Boundary condition
- Analyze stability condition
  - experimentally, abount dt = 0.7 ?
- Wave packet source
*/

/*
%%config-start%%
samplers:
  - name: buf
    type: framebuffer
    size: $default
    mipmap: true
    wrap: repeat
    filter: linear
    internal_format: GL_RG32F

programs:
  - name: mainImage1
    samplers:
      - buf
    output: buf
    substep:
      num_iter: 2
      samplers: [buf]

  - name: mainImage
    output: $default
    samplers:
      - buf

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

#include "common_v0.glsl"
#include "utils/hash_v0.glsl"

//
// Utilities
//

const vec2 XX = vec2(1.0, 0.0);
const vec2 YY = vec2(0.0, 1.0);

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


//
// Parameters
//

const float dt = 0.7;
const float dx = 1.0;
const float c  = 1.0;
const float mu = 0.005;
const int kBoundaryType = 0; // 0 : torus domain, 1 : Dirichlet, 2 : Neumann (reflection??)


//
// Display
//

void mainImage(out vec4 frag_color, in vec2 frag_coord, sampler2D buf){
  ivec2 texcoord = ivec2(floor(frag_coord));
  vec4 v = texelFetch(buf, texcoord, 0);
  vec3 color = vec3(v.x);
  // [debug] color by positive/negative
  float f = decode(texelFetch(buf, texcoord, 0)).x;
  color = vec3(max(f, 0) * 2.0, max(-f, 0) * 2.0, 0.0);
  frag_color = vec4(color, 1.0);
}


//
// PDE numerically
//

vec2 solve(vec2 p, sampler2D buf) {
  float f_old = decode(texture(buf, p)).y;
  float f     = decode(texture(buf, p)).x;

  // right, left, up, down
  float f_r = decode(texture(buf, p + XX / iResolution.xy)).x;
  float f_l = decode(texture(buf, p - XX / iResolution.xy)).x;
  float f_u = decode(texture(buf, p + YY / iResolution.xy)).x;
  float f_d = decode(texture(buf, p - YY / iResolution.xy)).x;

  // Explicit multistep formula (cf. above for derivation)
  //   f_n+1 = (1 / (1 + mu dt)) * (2 f_n - (1 - mu dt) f_n-1 + dt^2 c^2 ∆f_n)

  float div_grad_f = (f_r + f_l + f_u + f_d - 4 * f) / dot2(dx);
  float f_new = (1 / (1 + mu * dt)) * (2 * f - (1 - mu * dt) * f_old + dot2(dt * c) * div_grad_f);
  return vec2(f_new, f);
}


float getSource(vec2 frag_coord, vec2 source_coord) {
  float kBumpSize = 16.0; // pixel size
  vec2 r = frag_coord - source_coord;

  // Gaussian bump
  // #define INIT(R) exp(- 0.5 * dot2(R / (0.5 * kBumpSize)))

  // Cone
  // #define INIT(R) max(0.0, 1.0 - length(R) / kBumpSize)

  // Quandratic bump
  #define INIT(R) max(0.0, 1.0 - dot2(length(R) / kBumpSize))

  // Rectangle bump
  // #define INIT(R) float(reduceMax(abs(r)) < kBumpSize)

  // Disc bump
  // #define INIT(R) float(length(r) < kBumpSize)

  float f = INIT(r);
  return f;
}


float getMouseSource(vec2 frag_coord, vec4 _iMouse) {
  bool activated, down;
  vec2 last_click_pos, last_down_pos;
  getMouseState(_iMouse, /*out*/ activated, down, last_click_pos, last_down_pos);
  if (down && iFrame % 8 == 0) {
    float coin_toss = sign(hash11(iFrame) - 0.5);
    return coin_toss * getSource(frag_coord, last_down_pos);
  }
  return 0.0;
}


void mainImage1(out vec4 frag_color, vec2 frag_coord, sampler2D buf) {
  // Initialize
  if (iFrame <= 1) {
    float f = getSource(frag_coord, vec2(0.5, 0.5) * iResolution.xy);
    frag_color = encode(vec4(f, f, 0, 0));
    return;
  }

  // Solve
  vec2 p = frag_coord / iResolution.xy; // in [0, 1]^2
  vec2 ff = solve(p, buf);

  // Superpose interaction source
  ff += getMouseSource(frag_coord, iMouse);

  // Update
  frag_color = encode(vec4(ff, 0, 0));
}
