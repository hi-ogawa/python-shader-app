#define M_PI 3.14159
#define FLT_MAX 1e30

void getMouseStatus(
    vec4 mouse, out bool activated, out bool down,
    out vec2 last_click_pos, out vec2 last_down_pos) {
  activated = iMouse.x > 0.5;
  down = iMouse.z > 0.5;
  last_click_pos = abs(iMouse.zw) + vec2(0.5);
  last_down_pos = iMouse.xy + vec2(0.5);
}

mat2 rotate2(float t) {
  return mat2(cos(t), sin(t), -sin(t), cos(t));
}

mat3 rotate3(vec3 r) {
  mat2 x = rotate2(r.x);
  mat2 y = rotate2(r.y);
  mat2 z = rotate2(r.z);
  mat3 X = mat3(
      1.0,     0.0,     0.0,
      0.0, x[0][0], x[0][1],
      0.0, x[1][0], x[1][1]);
  mat3 Y = mat3(
    y[1][1],   0.0, y[1][0],
        0.0,   1.0,     0.0,
    y[0][1],   0.0, y[0][0]);
  mat3 Z = mat3(
    z[0][0], z[0][1],   0.0,
    z[1][0], z[1][1],   0.0,
        0.0,     0.0,   1.0);
  return Z * Y * X;
}

mat4 translate3(vec3 v) {
  return mat4(
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    vec4(v, 1.0));
}

vec3 sphericalCoordinate(vec3 p) {
  float r = length(p);
  if (r < 0.000001) {
    return vec3(r, 0.0, 0.0);
  }
  vec3 v = p / r;
  float theta = acos(v.z);
  float phi = atan(v.y, v.x);
  return vec3(r, theta, phi);
}

// TODO: Derive simpler closed formula from this or via quarternion
mat3 axisAngleTransform(vec3 v, float rad) {
  vec3 rtp = sphericalCoordinate(v);
  mat3 P = rotate3(vec3(0.0, rtp[1], rtp[2]));
  return P * rotate3(vec3(0.0, 0.0, rad)) * inverse(P);
}
