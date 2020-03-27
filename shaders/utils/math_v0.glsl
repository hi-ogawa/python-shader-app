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
