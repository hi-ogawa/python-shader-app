const vec3 OZN = vec3(1.0, 0.0, -1.0);

vec3 decodeGamma(vec3 color) {
  return pow(color, vec3(2.2));
}

vec3 encodeGamma(vec3 color) {
  return pow(color, vec3(1.0 / 2.2));
}
