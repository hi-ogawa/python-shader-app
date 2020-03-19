//
// PDE convection diffusion equation
// (use "substep" config for multiple executions of program within single display frame)
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
    internal_format: GL_R32F

programs:
  - name: mainImage1
    samplers:
      - buf
    output: buf
    substep:
      num_iter: 16
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


// North, East, South, West
const vec2 NN = vec2(+0.0, +1.0);
const vec2 EE = vec2(+1.0, +0.0);
const vec2 SS = -NN;
const vec2 WW = -EE;

float dot2(float v) { return dot(v, v); }
float dot2(vec2 v) { return dot(v, v); }
float reduceMax(vec2 v) { return max(v[0], v[1]); }

//
// Display
//
void mainImage(out vec4 frag_color, in vec2 frag_coord, sampler2D buf){
  vec2 p = frag_coord / iResolution.xy; // in [0, 1]^2
  float f = texture(buf, p).x;

  vec3 color = vec3(f);
  color = pow(color, vec3(1.0/2.2));
  frag_color = vec4(color, 1.0);
}

//
// PDE numerically
//

float solve(vec2 p, sampler2D buf) {
  // PDE Explicit method
  float f = texture(buf, p).x;
  float f_n = texture(buf, p + NN / iResolution.xy).x;
  float f_e = texture(buf, p + EE / iResolution.xy).x;
  float f_s = texture(buf, p + SS / iResolution.xy).x;
  float f_w = texture(buf, p + WW / iResolution.xy).x;

  const float dx = 1.0;
  const float dt = 0.25; // 2dim CFL condition : dt * mu / (4 dx^2) < 1

  const float mu = 1.0;
  const vec2 v = 0.01 * vec2(1.0, 0.5);

  vec2 grad_f = vec2(f_e - f_w, f_n - f_s) / (2 * dx);
  float div_grad_f = ((f_e + f_w - 2 * f) + (f_n + f_s - 2 * f)) / dot2(dx);
  float df_dt = - dot(v, grad_f) + mu * div_grad_f;
  f += dt * df_dt;
  return f;
}

float initialize(vec2 frag_coord, vec2 resolution) {
  vec2 kBumpPosition = vec2(0.5, 0.5);
  float kBumpSize = 48.0; // pixel size

  vec2 r = frag_coord - kBumpPosition * iResolution.xy;
  float f;

  // Gaussian bump
  // f = exp(- 0.5 * dot2(r / (0.5 * kBumpSize))); // in [0, 1]

  // Rectangle bump
  f = float(reduceMax(abs(r)) < kBumpSize);

  // Disc bump
  // f = float(length(r) < kBumpSize);
  return f;
}

void mainImage1(out vec4 frag_color, vec2 frag_coord, sampler2D buf) {
  if (iFrame <= 1) {
    frag_color.x = initialize(frag_coord, iResolution.xy);
    return;
  }

  vec2 p = frag_coord / iResolution.xy; // in [0, 1]^2
  frag_color.x = solve(p, buf);
}
