//
// gradient interpolation noise
//

float SCALE = 4.0;
float NUM_OCTAVES = 1.0;

// R -> [0, 1)
float hash11(float t) {
  return fract(sin(t * 56789) * 56789);
}

// R^2 -> [0, 1)
float hash21(vec2 uv) {
  return hash11(2.0 * hash11(uv[0]) + hash11(uv[1]));
}

vec2 hashGradient(vec2 uv) {
  float pi = 3.1415;
  float t = hash21(uv);
  return vec2(cos(2.0 * pi * t), sin(2.0 * pi * t));
}

float mix2(float f00, float f10, float f01, float f11, vec2 uv) {
  return mix(mix(f00, f10, uv[0]), mix(f01, f11, uv[0]), uv[1]);
}

// R^2 -> [0, 1)
float gradientNoise(vec2 uv) {
  vec2 uvi = floor(uv);
  vec2 uvf = uv - uvi;
  vec2 g00 = hashGradient(uvi + vec2(0.0, 0.0));
  vec2 g10 = hashGradient(uvi + vec2(1.0, 0.0));
  vec2 g01 = hashGradient(uvi + vec2(0.0, 1.0));
  vec2 g11 = hashGradient(uvi + vec2(1.0, 1.0));
  float f00 = dot(g00, uvf - vec2(0.0, 0.0));
  float f10 = dot(g10, uvf - vec2(1.0, 0.0));
  float f01 = dot(g01, uvf - vec2(0.0, 1.0));
  float f11 = dot(g11, uvf - vec2(1.0, 1.0));
  float t = mix2(f00, f10, f01, f11, smoothstep(vec2(0.0), vec2(1.0), uvf));
  // Normalize via upper/lower bound = +- 1 / sqrt(2) ~ 0.7
  return (t / 0.7 + 1.0) * 0.5;
}

float noise(vec2 uv) {
  float result = 0.0;
  for (float i = 0.0; i < NUM_OCTAVES; i++) {
    float p = pow(2.0, i);
    result += (gradientNoise(uv * p) / p);
  }
  result /= (pow(2.0, NUM_OCTAVES) - 1.0) / (pow(2.0, NUM_OCTAVES - 1.0));
  return result;
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv =  frag_coord / iResolution.y;
  uv = uv * SCALE;
  float fac = noise(uv);
  frag_color = vec4(vec3(fac), 1.0);
}
