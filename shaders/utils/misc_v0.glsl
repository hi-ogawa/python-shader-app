const vec3 OZN = vec3(1.0, 0.0, -1.0);

vec3 decodeGamma(vec3 color) {
  return pow(color, vec3(2.2));
}

vec3 encodeGamma(vec3 color) {
  return pow(color, vec3(1.0 / 2.2));
}

vec3 Misc_hue(float t) {
  vec3 color = 0.5 + 0.5 * cos(2.0 * M_PI * (t - vec3(0.0, 1.0, 2.0) / 3.0));
  return color;
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

uint Misc_reverseBits(uint x) {
  x = ((x & 0x55555555u) <<  1u) | ((x & 0xaaaaaaaau) >>  1u);  // 0x5 = '0101', 0xa = '1010'
  x = ((x & 0x33333333u) <<  2u) | ((x & 0xccccccccu) >>  2u);  // 0x3 = '0011', 0xc = '1100'
  x = ((x & 0x0f0f0f0fu) <<  4u) | ((x & 0xf0f0f0f0u) >>  4u);
  x = ((x & 0x00ff00ffu) <<  8u) | ((x & 0xff00ff00u) >>  8u);
  x = ((x & 0x0000ffffu) << 16u) | ((x & 0xffff0000u) >> 16u);
  return x;
}

// van der Corput sequence with base = 2
float Misc_corput2(uint n) {
  uint rev = Misc_reverseBits(n);
  const float kPow2_32 = uintBitsToFloat(uint(32 + 127) << 23u); // or use float(0xffffffffu) = 2^32 - 1
  return float(rev) / kPow2_32;
}

// 2dim Hammersley set (assume n \in {1, 2, ..., n_max})
vec2 Misc_hammersley2D(uint n, uint n_max) {
  // - Offset by "1 / 2 N" so it fits in (0, 1)^2
  // - Precise bound is [dx, 1 - dx] x [dy, 1 - dy] where
  //     dx = 1 / 2 N
  //     dy = 1 / 2^k  (s.t. N < 2^k)
  return vec2((float(n) - 0.5) / float(n_max), Misc_corput2(n));
}

// Generalized Corput sequence with arbitrary base
float Misc_corput(uint n, uint base) {
  // assert base >= 2
  uint rev = 0u;
  uint pow_base = 1u;
  while (n > 0u) {
    uint d = n / base;
    uint r = n - d * base;
    n = d;
    rev = base * rev + r;
    pow_base *= base;
  }
  return float(rev) / float(pow_base);
}

vec2 Misc_halton2D(uint n) {
  // assert n > 1
  return vec2(Misc_corput(n, 2u), Misc_corput(n, 3u));
}
