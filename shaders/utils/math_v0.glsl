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

mat3 q_to_so3(vec4 q) {
  float s = q.w;
  vec3 v = q.xyz;
  mat3 I = mat3(1.0);
  mat3 Cv = mat_cross(v);
  return 2.0 * outer(v, v) + (dot2(s) - dot2(v)) * I + 2.0 * s * Cv;
}

vec3 orthogonalize(vec3 v, vec3 n) {
  return v - dot(n, v) * n;
}
