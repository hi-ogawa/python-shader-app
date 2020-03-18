// By Chris Wellons https://nullprogram.com/blog/2018/07/31/
uint hash11u(uint x) {
  x ^= x >> 16u;
  x *= 0x7feb352du;
  x ^= x >> 15u;
  x *= 0x846ca68bu;
  x ^= x >> 16u;
  return x;
}

uint hash21u(uvec2 x) {
  return hash11u(hash11u(x[0]) + x[1]);
}

uint hash31u(uvec3 x) {
  return hash11u(hash11u(hash11u(x[0]) + x[1]) + x[2]);
}

uvec2 hash12u(uint x) {
  return uvec2(hash11u(x), hash21u(uvec2(x, 1u)));
}

float uintToUnitFloat(uint x) {
  return float(x >> 9u) / float(1u << 23u);
}

float hash11(float x) {
  return uintToUnitFloat(hash11u(floatBitsToUint(x)));
}

float hash21(vec2 x) {
  return uintToUnitFloat(hash21u(floatBitsToUint(x)));
}

float hash31(vec3 x) {
  return uintToUnitFloat(hash31u(floatBitsToUint(x)));
}

vec2 hash12(float x) {
  return vec2(hash11(x), hash21(vec2(x, 1.0)));
}

vec3 hash13(float x) {
  return vec3(hash11(x), hash21(vec2(x, 1.0)), hash21(vec2(x, 2.0)));
}

vec3 hash23(vec2 x) {
  return vec3(hash21(x), hash31(vec3(x, 1.0)), hash31(vec3(x, 2.0)));
}
