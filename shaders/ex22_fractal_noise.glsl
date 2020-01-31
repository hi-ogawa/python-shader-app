#include "common_v0.glsl"

float SCALE_TIME = 0.2;
float SCALE = 16.0;
float NUM_OCTAVES = 4.0;
mat3 FRACTAL_XFORM = rotate3(vec3(0.2, 0.2, 0.2) * M_PI);

bool USE_ISOSURFACE = false;
float ISOSURFACE_VALUE_WIDTH = 0.06;
float ISOSURFACE_NUM_REPEAT = 2.0;

uint hash31u(uvec3 p) {
  #define ROT(x, r)       ((x << r) | (x >> (32u - r)))
  #define MIX2(x0, x1, r)  x0 = x0 + x1; x1 = x0 ^ ROT(x1, r);
  #define MIX4(x0, x1, x2, x3) \
    MIX2(x0, x1, 14u); \
    MIX2(x0, x2, 15u); \
    MIX2(x1, x3, 17u); \
    MIX2(x2, x3, 18u); \

  uint x0 = 0x12312312u;
  uint x1 = 0x45645645u;
  uint x2 = 0x78978978u;
  uint x3 = 0xabcabcabu;

  x0 = x0 ^ p[0];
  MIX4(x0, x1, x2, x3);
  x3 = x3 ^ p[0];

  x0 = x0 ^ p[1];
  MIX4(x0, x1, x2, x3);
  x3 = x3 ^ p[1];

  x0 = x0 ^ p[2];
  MIX4(x0, x1, x2, x3);
  x3 = x3 ^ p[2];

  MIX4(x0, x1, x2, x3);
  MIX4(x0, x1, x2, x3);
  return x0 ^ x1 ^ x2 ^ x3;

  #undef ROT
  #undef MIX2
  #undef MIX4
}

float hash31(vec3 p) {
  return float(hash31u(floatBitsToUint(p))) / float(0xffffffffu);
}

float valueNoise(vec3 p) {
  vec3 pi = floor(p);
  vec3 pf = p - pi;
  float f000 = hash31(pi + vec3(0.0, 0.0, 0.0));
  float f100 = hash31(pi + vec3(1.0, 0.0, 0.0));
  float f010 = hash31(pi + vec3(0.0, 1.0, 0.0));
  float f110 = hash31(pi + vec3(1.0, 1.0, 0.0));
  float f001 = hash31(pi + vec3(0.0, 0.0, 1.0));
  float f101 = hash31(pi + vec3(1.0, 0.0, 1.0));
  float f011 = hash31(pi + vec3(0.0, 1.0, 1.0));
  float f111 = hash31(pi + vec3(1.0, 1.0, 1.0));
  vec3 pf_smooth = smoothstep(vec3(0.0), vec3(1.0), pf);
  return mix3(f000, f100, f010, f110, f001, f101, f011, f111, pf_smooth);
}

float fractalNoise(vec3 v, float num_octaves) {
  float result = 0.0;
  float p = 1.0;
  for (float i = 0.0; i < num_octaves; i++) {
    result += (valueNoise(v) / p);
    p = 2.0 * p;
    v = 2.0 * FRACTAL_XFORM * v;
  }
  result /= (p - 1.0) / p * 2.0; // here p = pow(2, num_octaves)
  return result;
}

float smoothBump(float fac, float bump_at, float bump_width) {
  return 1.0 - smoothstep(0.0, bump_width / 2.0, abs(fac - bump_at));
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv = frag_coord / iResolution.y;
  float fac_noise = fractalNoise(vec3(SCALE * uv, SCALE_TIME * iTime), NUM_OCTAVES);

  float fac = 0.0;
  if (USE_ISOSURFACE) {
    fac += smoothBump(fac_noise, 0.5, ISOSURFACE_VALUE_WIDTH);
    for (float j = 1.0; j <= ISOSURFACE_NUM_REPEAT; j++) {
      fac += smoothBump(fac_noise, 0.5 + 2.0 * j * ISOSURFACE_VALUE_WIDTH, ISOSURFACE_VALUE_WIDTH);
      fac += smoothBump(fac_noise, 0.5 - 2.0 * j * ISOSURFACE_VALUE_WIDTH, ISOSURFACE_VALUE_WIDTH);
    }
  } else {
    fac = fac_noise;
  }

  frag_color = vec4(vec3(fac), 1.0);
}
