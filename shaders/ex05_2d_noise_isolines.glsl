//
// 2d noise contour
//

float M_PI = 3.1415;

float SCALE = 4.0;
float NUM_OCTAVES = 2.0;
float SCALE_TIME = 0.1;

float SCALE_CONTOUR = 32.0;
vec2 CLIP_RANGE = vec2(0.85, 1.0);
vec3 COLOR1 = vec3(1.0, 0.0, 1.0);
vec3 COLOR2 = vec3(0.0, 1.0, 1.0);

// R -> [0, 1)
float hash11(float t) {
  return fract(sin(t * 56789.0) * 56789.0);
}

// R^2 -> [0, 1)
float hash21(vec2 uv) {
  return hash11(hash11(uv[0]) + 2.0 * hash11(uv[1]));
}

vec2 hashGradient2(vec2 uv) {
  float t = hash21(uv);
  return vec2(cos(2.0 * M_PI * t), sin(2.0 * M_PI * t));
}

float mix2(float f00, float f10, float f01, float f11, vec2 uv) {
  return mix(mix(f00, f10, uv[0]), mix(f01, f11, uv[0]), uv[1]);
}

vec2 rotate2(vec2 uv, float r) {
  mat2 R = mat2(
    cos(r), sin(r),
   -sin(r), cos(r)
  );
  return R * uv;
}

// R^2 -> [0, 1)
// support additional argument to rotate gradient
float gradientNoise(vec2 uv, float r) {
  vec2 uvi = floor(uv);
  vec2 uvf = uv - uvi;
  vec2 g00 = rotate2(hashGradient2(uvi + vec2(0.0, 0.0)), r);
  vec2 g10 = rotate2(hashGradient2(uvi + vec2(1.0, 0.0)), r);
  vec2 g01 = rotate2(hashGradient2(uvi + vec2(0.0, 1.0)), r);
  vec2 g11 = rotate2(hashGradient2(uvi + vec2(1.0, 1.0)), r);
  float f00 = dot(g00, uvf - vec2(0.0, 0.0));
  float f10 = dot(g10, uvf - vec2(1.0, 0.0));
  float f01 = dot(g01, uvf - vec2(0.0, 1.0));
  float f11 = dot(g11, uvf - vec2(1.0, 1.0));
  float t = mix2(f00, f10, f01, f11, smoothstep(vec2(0.0), vec2(1.0), uvf));

  // Normalize via upper/lower bound = +- 1 / sqrt(2) ~ 0.7
  return (t / 0.7 + 1.0) * 0.5;
}

float noise(vec2 uv, float r) {
  float result = 0.0;
  for (float i = 0.0; i < NUM_OCTAVES; i++) {
    float p = pow(2.0, i);
    result += (gradientNoise(uv * p, r) / p);
  }
  result /= (pow(2.0, NUM_OCTAVES) - 1.0) / (pow(2.0, NUM_OCTAVES - 1.0));
  return result;
}

float wave(float t) {
  return 0.5 * (1.0 - cos(SCALE_CONTOUR * M_PI * t));
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv =  SCALE * frag_coord / iResolution.y;

  float noise_fac = noise(uv, SCALE_TIME * 2.0 * M_PI * iTime);
  float contour_fac = wave(noise_fac);
  float clip = smoothstep(CLIP_RANGE[0], CLIP_RANGE[1], contour_fac);
  vec3 color = mix(COLOR1, COLOR2, noise_fac);

  frag_color = vec4(color * clip, 1.0);
}
