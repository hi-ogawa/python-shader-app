#define M_PI 3.14159

float reduce(vec2 v) {
  return v[0] + v[1];
}

float reduce(vec3 v) {
  return v[0] + v[1] + v[2];
}

float reduceMax(vec3 v) {
  return max(v[0], max(v[1], v[2]));
}

float reduceMin(vec3 v) {
  return min(v[0], min(v[1], v[2]));
}

int reduceArgmax(vec3 v) {
  int i = 0;
  float t = v[0];
  for (int j = 1; j <= 2; j++) {
    if (t < v[j]) {
      i = j;
      t = v[j];
    }
  }
  return i;
}

// aka. ReLU
float clamp0(float x) {
  return max(0.0, x);
}

#define FOREACH_FLOAT_TYPES(_) \
  _(float) \
  _(vec2)  \
  _(vec3)  \
  _(vec4)  \

#define DEFINE_DOT2(TYPE) float dot2(TYPE v) { return dot(v, v); }
FOREACH_FLOAT_TYPES(DEFINE_DOT2)

float mix2(float f00, float f01, float f10, float f11, vec2 p) {
  return mix(mix(f00, f01, p.y), mix(f10, f11, p.y), p.x);
}

float mix3(
    float f000, float f001, float f010, float f011,
    float f100, float f101, float f110, float f111, vec3 p) {
  return mix(
      mix2(f000, f001, f010, f011, p.yz),
      mix2(f100, f101, f110, f111, p.yz), p.x);
}

float pow2(float x) {
  return x*x;
}

float pow3(float x) {
  return x*x*x;
}

float pow4(float x) {
  return x*x*x*x;
}

float pow5(float x) {
  return x*x*x*x*x;
}

vec2 pow2(vec2 x) { return x * x; }
vec3 pow2(vec3 x) { return x * x; }
vec4 pow2(vec4 x) { return x * x; }
mat2 pow2(mat2 x) { return x * x; }
mat3 pow2(mat3 x) { return x * x; }
mat4 pow2(mat4 x) { return x * x; }

#define DEFINE_DIAG(N)             \
  mat##N diag(vec##N v) {          \
    mat##N m = mat##N(0.0);        \
    for (int i = 0; i < N; i++) {  \
      m[i][i] = v[i];              \
    }                              \
    return m;                      \
  }                                \

DEFINE_DIAG(2)
DEFINE_DIAG(3)
DEFINE_DIAG(4)

mat3 mat_cross(vec3 v) {
  return mat3(
     0.0, +v.z, -v.y,
    -v.z,  0.0, +v.x,
    +v.y, -v.x,  0.0);
}

mat3 outer(vec3 u, vec3 v) {
  return mat3(u * v.x, u * v.y, u * v.z);
}

mat2 outer(vec2 u, vec2 v) {
  return mat2(u * v.x, u * v.y);
}

mat2 outer2(vec2 u) { return outer(u, u); }
mat3 outer2(vec3 u) { return outer(u, u); }

vec4 q_mul(vec4 q, vec4 p) {
  float s1 = q.w;  vec3 v1 = q.xyz;
  float s2 = p.w;  vec3 v2 = p.xyz;
  float s = s1 * s2 - dot(v1, v2);
  vec3 v = s1 * v2 + s2 * v1 + cross(v1, v2);
  return vec4(v, s);
}

vec4 q_conj(vec4 q) {
  return vec4(-q.xyz, q.w);
}

vec3 q_apply(vec4 q, vec3 v) {
  vec4 p = vec4(v, 0.0);
  return q_mul(q_mul(q, p), q_conj(q)).xyz;
}

vec3 q_applyInv(vec4 q, vec3 v) {
  return q_apply(q_conj(q), v);
}

mat3 q_toSo3(vec4 q) {
  float s = q.w;
  vec3 v = q.xyz;
  mat3 I = mat3(1.0);
  mat3 Cv = mat_cross(v);
  return 2.0 * outer(v, v) + (dot2(s) - dot2(v)) * I + 2.0 * s * Cv;
}

vec4 q_fromAxisAngle(vec3 u, float t) {
  return vec4(sin(0.5 * t) * u, cos(0.5 * t));
}

vec4 q_fromAxisAngleVector(vec3 v) {
  if (length(v) < 1e-7) { return vec4(vec3(0.0), 1.0); }
  return q_fromAxisAngle(normalize(v), length(v));
}

vec3 orthogonalize(vec3 v, vec3 n) {
  // mat3(1.0) - outer2(n, n)
  return v - dot(n, v) * n;
}

const vec2 c_0 = vec2(0.0, 0.0);
const vec2 c_1 = vec2(1.0, 0.0);
const vec2 c_i = vec2(0.0, 1.0);

vec2 c_conj(vec2 z) {
  return vec2(z.x, -z.y);
}

mat2 c_mul(vec2 z) {
  // complex multiplication as scale/rotation
  return mat2(z.x, z.y, -z.y, z.x);
}

vec2 c_inv(vec2 z) {
  return c_conj(z) / dot2(z);
}

vec2 c_pow(vec2 z, int n) {
  vec2 ret = c_1;
  for (int i = 0; i < n; i++) {
    ret = c_mul(z) * ret;
  }
  return ret;
}
