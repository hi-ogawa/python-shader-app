const vec3 OZN = vec3(1.0, 0.0, -1.0);

vec3 decodeGamma(vec3 color) {
  return pow(color, vec3(2.2));
}

vec3 encodeGamma(vec3 color) {
  return pow(color, vec3(1.0 / 2.2));
}

vec3 Misc_tonemap(vec3 L, float exposure, float log_curve_l, float log_curve_a) {
  // exposure
  L *= pow(2.0, exposure);

  // log curve
  float l = log_curve_l;
  float a = log_curve_a;
  vec3 x = L;
  L = min(x, vec3(l)) + log(a * (max(x, vec3(l)) - l) + 1.0) / a;

  // gamma
  return encodeGamma(L);
}
