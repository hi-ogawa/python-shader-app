#define M_PI 3.14159
#define FLT_MAX 1e30

void getMouseState(
    vec4 mouse, out bool activated, out bool down,
    out vec2 last_click_pos, out vec2 last_down_pos) {
  activated = mouse.x > 0.5;
  down = mouse.z > 0.5;
  last_click_pos = abs(mouse.zw) + vec2(0.5);
  last_down_pos = mouse.xy + vec2(0.5);
}

float intersect_Line_Plane(vec3 p, vec3 v, vec3 q, vec3 n) {
  // <p + t v - q, n> = 0
  // assert: not v // n
  return dot(q - p, n) / dot(v, n);
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

mat4 perspectiveTransform(float yfov, float aspect_ratio, float near, float far) {
  float a = tan(yfov / 2.0);  // half y
  float b = aspect_ratio * a; // half x
  float c = 2.0 * far * near / (far - near);
  float d = - (far + near) / (far - near);
  return mat4(
  1.0/a,   0.0,  0.0,  0.0,
    0.0, 1.0/b,  0.0,  0.0,
    0.0,   0.0,    c, -1.0,
    0.0,   0.0,    d,  0.0);
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

mat3 zframeTransform(vec3 z) {
  // assert |z| = 1
  vec3 x = cross(z, (abs(z.x) < 0.9) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0));
  x = normalize(x);
  vec3 y = cross(z, x);
  return mat3(x, y, z);
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

// NOTE: this doesn't work when lookat_loc != 0 (see pivotTransform_v2)
mat4 pivotTransform(vec3 init_loc, vec3 lookat_loc, vec2 delta) {
  // horizontal move
  vec3 roty = vec3(0.0, -delta.x, 0.0);
  vec3 loc_tmp = rotate3(roty) * init_loc;
  mat4 xform_tmp = lookatTransform(
      loc_tmp, lookat_loc, vec3(0.0, 1.0, 0.0));

  // vertical move
  vec3 rotx_axis = vec3(xform_tmp[0]);
  float rotx_angle = delta.y;
  mat3 rotx = axisAngleTransform(rotx_axis, rotx_angle);
  mat4 xform = mat4(rotx) * xform_tmp;
  return xform;
}

mat4 pivotTransform_v2(vec3 init_loc, vec3 lookat_loc, vec2 delta) {
  // relative to lookat_loc
  vec3 init_loc_rel = init_loc - lookat_loc;

  // horizontal move
  mat3 roty = rotate3(vec3(0.0, -delta.x, 0.0));
  vec3 loc_rel_tmp = roty * init_loc_rel;
  mat4 xform_tmp = lookatTransform(loc_rel_tmp, vec3(0.0), vec3(0.0, 1.0, 0.0));

  // vertical move
  vec3 rotx_axis = vec3(xform_tmp[0]);
  float rotx_angle = delta.y;
  mat3 rotx = axisAngleTransform(rotx_axis, rotx_angle);
  mat4 xform = mat4(rotx) * xform_tmp;

  // move to lookat_loc
  return translate3(+lookat_loc) * xform;
}

float Quick_hash(float t, float scale) {
  return fract(sin(t * scale) * scale);
}

vec3 Quick_color(float t) {
  vec3 color = 0.5 + 0.5 * cos(2.0 * M_PI * (t - vec3(0.0, 1.0, 2.0) / 3.0));
  color = smoothstep(vec3(-0.1), vec3(0.9), color);
  return color;
}
