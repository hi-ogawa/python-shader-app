#define M_PI 3.14159
#define FLT_MAX 1e30

void getMouseState(
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

vec3 inverseSphericalCoordinate(vec3 p) {
  return p.x * vec3(
    sin(p.y) * cos(p.z),
    sin(p.y) * sin(p.z),
    cos(p.y));
}

// TODO: Derive simpler closed formula from this or via quarternion
mat3 axisAngleTransform(vec3 v, float rad) {
  vec3 rtp = sphericalCoordinate(v);
  mat3 P = rotate3(vec3(0.0, rtp[1], rtp[2]));
  return P * rotate3(vec3(0.0, 0.0, rad)) * inverse(P);
}

// [0, W] x [0, H]  -->  [-X/2, X/2] x [-tan(yfov/2), tan(yfov/2)]
// s.t. aspect ratio preserved
mat3 inverseViewTransform(float yfov, vec2 Resolution) {
  float w = Resolution.x;
  float h = Resolution.y;
  float half_y = tan(yfov / 2.0);
  float half_x = (w / h) * half_y;
  vec2 a = vec2(-half_x, -half_y);
  float Sy = (2.0 * half_y) / h;
  mat3 xform = mat3(
       Sy, 0.0, 0.0,
      0.0,  Sy, 0.0,
      a.x, a.y, 1.0);
  return xform;
}

mat4 lookatTransform(vec3 loc, vec3 lookat_loc, vec3 up) {
  vec3 z = normalize(loc - lookat_loc);
  vec3 x = - cross(z, up);
  vec3 y = cross(z, x);
  mat4 xform = mat4(
      x,   0.0,
      y,   0.0,
      z,   0.0,
      loc, 1.0);
  return xform;
}

float mix2(float f00, float f10, float f01, float f11, vec2 uv) {
  return mix(mix(f00, f10, uv.x), mix(f01, f11, uv.x), uv.y);
}

float mix3(
    float f000, float f100, float f010, float f110,
    float f001, float f101, float f011, float f111,
    vec3 v) {
  float fxy0 = mix2(f000, f100, f010, f110, v.xy);
  float fxy1 = mix2(f001, f101, f011, f111, v.xy);
  return mix(fxy0, fxy1, v.z);
}

float Quick_hash(float t, float scale) {
  return fract(sin(t * scale) * scale);
}

vec3 Quick_color(float t) {
  vec3 color = 0.5 + 0.5 * cos(2.0 * M_PI * (t - vec3(0.0, 1.0, 2.0) / 3.0));
  color = smoothstep(vec3(-0.1), vec3(0.9), color);
  return color;
}
