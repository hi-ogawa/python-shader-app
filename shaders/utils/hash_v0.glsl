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

uvec2 hash22u(uvec2 x) {
  return uvec2(hash21u(x), hash31u(uvec3(x, 1u)));
}

uvec2 hash32u(uvec3 x) {
  return hash22u(hash22u(x.xy) + x.z);
}

uvec2 hash12u(uint x) {
  return uvec2(hash11u(x), hash21u(uvec2(x, 1u)));
}

uvec2 hash42u(uvec4 x) {
  return hash22u(hash22u(x.xy) + x.zw);
}


//
// Float variants
//

float uintToUnitFloat(uint x) {
  return float(x >> 9u) / float(1u << 23u);
}

vec2 uintToUnitFloat(uvec2 x) {
  return vec2(x >> 9u) / vec2(1u << 23u);
}

vec3 uintToUnitFloat(uvec3 x) {
  return vec3(x >> 9u) / vec3(1u << 23u);
}

vec4 uintToUnitFloat(uvec4 x) {
  return vec4(x >> 9u) / vec4(1u << 23u);
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

vec2 hash22(vec2 x) {
  return uintToUnitFloat(hash22u(floatBitsToUint(x)));
}

vec2 hash32(vec3 x) {
  return uintToUnitFloat(hash32u(floatBitsToUint(x)));
}

vec2 hash42(vec4 x) {
  return uintToUnitFloat(hash42u(floatBitsToUint(x)));
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
