#define M_PI 3.14159

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
