// require: [math_v0.glsl, hash_v0.glsl]

float Noise_valueNoise(vec3 p) {
  vec3 pi = floor(p);
  vec3 pf = smoothstep(vec3(0.0), vec3(1.0), fract(p));
  const vec3 X = vec3(1.0, 0.0, 0.0);
  const vec3 Y = vec3(0.0, 1.0, 0.0);
  const vec3 Z = vec3(0.0, 0.0, 1.0);
  return mix3(
      hash31(pi + (0 + 0 + 0)),
      hash31(pi + (0 + 0 + Z)),
      hash31(pi + (0 + Y + 0)),
      hash31(pi + (0 + Y + Z)),
      hash31(pi + (X + 0 + 0)),
      hash31(pi + (X + 0 + Z)),
      hash31(pi + (X + Y + 0)),
      hash31(pi + (X + Y + Z)),
      pf);
}
