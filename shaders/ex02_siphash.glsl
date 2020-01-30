//
// siphash-like hash
//

#define ROT(x, r)       ((x << r) | (x >> (32u - r)))
#define MIX2(x0, x1, r)  x0 = x0 + x1; x1 = x0 ^ ROT(x1, r);
#define MIX4(x0, x1, x2, x3) \
  MIX2(x0, x1, 14u); \
  MIX2(x0, x2, 15u); \
  MIX2(x0, x3, 16u); \
  MIX2(x1, x3, 17u); \
  MIX2(x2, x3, 18u); \

uint hash_x0 = 0x12312312u;
uint hash_x1 = 0x45645645u;
uint hash_x2 = 0x78978978u;
uint hash_x3 = 0xabcabcabu;

uint hash11u(uint p) {
  uint x0 = hash_x0;
  uint x1 = hash_x1;
  uint x2 = hash_x2;
  uint x3 = hash_x3;

  x0 = x0 ^ p;
  MIX4(x0, x1, x2, x3);
  x3 = x3 ^ p;

  MIX4(x0, x1, x2, x3);
  MIX4(x0, x1, x2, x3);
  return x0 ^ x1 ^ x2 ^ x3;
}

uint hash21u(uvec2 p) {
  uint x0 = hash_x0;
  uint x1 = hash_x1;
  uint x2 = hash_x2;
  uint x3 = hash_x3;

  x0 = x0 ^ p[0];
  MIX4(x0, x1, x2, x3);
  x3 = x3 ^ p[0];

  x0 = x0 ^ p[1];
  MIX4(x0, x1, x2, x3);
  x3 = x3 ^ p[1];

  MIX4(x0, x1, x2, x3);
  MIX4(x0, x1, x2, x3);
  return x0 ^ x1 ^ x2 ^ x3;
}

// Return mixed four uints as vector
uvec4 hash24u(uvec2 p) {
  uvec4 q;
  uint x0 = hash_x0;
  uint x1 = hash_x1;
  uint x2 = hash_x2;
  uint x3 = hash_x3;

  x0 = x0 ^ p[0];
  MIX4(x0, x1, x2, x3);
  x3 = x3 ^ p[0];

  x0 = x0 ^ p[1];
  MIX4(x0, x1, x2, x3);
  x3 = x3 ^ p[1];

  MIX4(x0, x1, x2, x3);
  MIX4(x0, x1, x2, x3);
  return uvec4(x0, x1, x2, x3);
}

uint hash31u(uvec3 p) {
  uint x0 = hash_x0;
  uint x1 = hash_x1;
  uint x2 = hash_x2;
  uint x3 = hash_x3;

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
}

#undef ROT
#undef MIX2
#undef MIX4


// Use lower 23 bits to make [0, 1)
float uint_to_float(uint x) {
  //  2^{127 - 127} * 1.x[22..0] - 1.0
  return uintBitsToFloat((127u << 23u) | (0x7fffffu & x)) - 1.0;
}

// Produce float [0, 1) from given specified bits of uint
float uint_to_float_v2(uint x, uint num_bits, uint offset_bits) {
  uint y = (x >> offset_bits);
  return uint_to_float(y << (23u - num_bits));
}

// [0, 2^32) -> [0, 1) x [0, 1)
// where float output has resolution of (1 / 2)^16
vec2 uint_to_vec2(uint x) {
  uint x_hi = (x >> 16);
  uint x_lo = (x & 0xffffu);
  return vec2(
      uint_to_float(x_hi << (23u - 16u)),
      uint_to_float(x_lo << (23u - 16u)));
}


float SCALE = 3.0;
uint OFFSET = 0u;
float SCALE_TIME = 100.0;

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  uvec2 co = OFFSET + uvec2(floor((frag_coord - vec2(0.5)) / SCALE));
  co += uint(floor(iTime * SCALE_TIME));

  // 1. hash11u
  {
    uint z = co.x + co.y * 18181u;
    float fac = uint_to_float(hash11u(z));
    frag_color = vec4(vec3(fac), 1.0);
  }

  // 2. hash21u
  {
    float fac = uint_to_float(hash21u(co));
    // frag_color = vec4(vec3(fac), 1.0);
  }

  // 3. hash21u (pick up certain bits)
  {
    float fac = uint_to_float_v2(hash21u(co), 4u, 11u);
    // frag_color = vec4(vec3(fac), 1.0);
  }

  // 4. hash21u (from float)
  {
    uvec2 p = floatBitsToUint(frag_coord);
    float fac = uint_to_float(hash21u(p));
    // frag_color = vec4(vec3(fac), 1.0);
  }

  // 5. hash31
  {
    vec2 p = uint_to_vec2(hash21u(co));
    vec2 q = uint_to_vec2(hash31u(uvec3(co, 1u)));
    vec3 color = vec3(p.xy, q.x);
    // frag_color = vec4(color, 1.0);
  }

  // 6. hash24u
  {
    uvec4 p = hash24u(co);
    vec3 color = vec3(
        uint_to_float(p.x),
        uint_to_float(p.y),
        uint_to_float(p.z));
    // frag_color = vec4(color, 1.0);
  }
}
