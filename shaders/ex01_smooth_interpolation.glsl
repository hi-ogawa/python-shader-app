//
// value interpolation noise
//

float SCALE = 4.0;
float NUM_OCTAVES = 8.0;

// R -> [0, 1)
float hash11(float t) {
  return fract(sin(t * 56789) * 56789);
}

// R^2 -> [0, 1)
float hash21(vec2 uv) {
  return hash11(2.0 * hash11(uv[0]) + hash11(uv[1]));
}

float mix2(float f00, float f10, float f01, float f11, vec2 uv) {
  return mix(mix(f00, f10, uv[0]), mix(f01, f11, uv[0]), uv[1]);
}

// R^2 -> [0, 1)
float valueNoise(vec2 uv) {
  vec2 uvi = floor(uv);
  vec2 uvf = uv - uvi;
  float f00 = hash21(uvi + vec2(0.0, 0.0));
  float f10 = hash21(uvi + vec2(1.0, 0.0));
  float f01 = hash21(uvi + vec2(0.0, 1.0));
  float f11 = hash21(uvi + vec2(1.0, 1.0));
  return mix2(f00, f10, f01, f11, smoothstep(vec2(0.0), vec2(1.0), uvf));
}

float noise(vec2 uv) {
  float result = 0.0;
  for (float i = 0.0; i < NUM_OCTAVES; i++) {
    float p = pow(2.0, i);
    result += (valueNoise(uv * p) / p);
  }
  result /= (pow(2.0, NUM_OCTAVES) - 1.0) / (pow(2.0, NUM_OCTAVES - 1.0));
  return result;
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv = SCALE * frag_coord / iResolution.y;
  float fac = noise(uv);
  frag_color = vec4(vec3(fac), 1.0);
}
