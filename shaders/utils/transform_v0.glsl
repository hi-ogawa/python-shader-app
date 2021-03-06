mat2 T_rotate2(float t) {
  return mat2(cos(t), sin(t), -sin(t), cos(t));
}

mat3 T_rotate3(vec3 r) {
  mat2 x = T_rotate2(r.x);
  mat2 y = T_rotate2(r.y);
  mat2 z = T_rotate2(r.z);
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

mat4 T_translate3(vec3 v) {
  return mat4(
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    vec4(v, 1.0));
}

mat3 T_scale3(vec3 v) {
  return mat3(
    v.x, 0.0, 0.0,
    0.0, v.y, 0.0,
    0.0, 0.0, v.z);
}

mat3 T_translate2(vec2 v) {
  return mat3(
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    vec3(v, 1.0));
}

mat2 T_scale2(vec2 v) {
  return mat2(
    v.x, 0.0,
    0.0, v.y);
}

vec2 T_apply2(mat3 xform, vec2 v) {
  return vec2(xform * vec3(v, 1.0));
}

mat4 T_lookAt(vec3 p, vec3 lookat_p, vec3 up) {
  vec3 z = normalize(p - lookat_p);
  vec3 x = - normalize(cross(z, up));
  vec3 y = cross(z, x);
  mat4 xform = mat4(
      x, 0.0,
      y, 0.0,
      z, 0.0,
      p, 1.0);
  return xform;
}

mat4 T_perspective(float yfov, float aspect_ratio, float znear, float zfar) {
  float half_y = tan(yfov / 2.0);
  float half_x = aspect_ratio * half_y;
  float a = - (zfar + znear) / (zfar - znear);
  float b = - 2 * zfar * znear / (zfar - znear);
  float c = 1.0 / half_x;
  float d = 1.0 / half_y;
  float e = - 1.0;
  return mat4(
      c, 0, 0, 0,
      0, d, 0, 0,
      0, 0, a, e,
      0, 0, b, 0);
}

// [0, W] x [0, H]  -->  [-X/2, X/2] x [-tan(yfov/2), tan(yfov/2)]
// s.t. aspect ratio preserved
mat3 T_invView(float yfov, vec2 resolution) {
  float w = resolution.x;
  float h = resolution.y;
  float half_y = tan(yfov / 2.0);
  float half_x = (w / h) * half_y;
  float a = -half_x;
  float b = -half_y;
  float c = 1.0;
  float s = (2.0 * half_y) / h;
  mat3 xform = mat3(
      s, 0, 0,
      0, s, 0,
      a, b, c);
  return xform;
}

mat3 T_zframe(vec3 z) {
  vec3 x = cross(z, (abs(z.x) < 0.9) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0));
  x = normalize(x);
  vec3 y = cross(z, x);
  return mat3(x, y, z);
}

vec3 T_sphericalToCartesian(vec3 p) {
  vec3 v = vec3(
    sin(p.y) * cos(p.z),
    sin(p.y) * sin(p.z),
    cos(p.y));
  return p.x * v;
}

vec3 T_cartesianToSpherical(vec3 p) {
  float r = length(p);
  if (r < 1e-7) {
    return vec3(r, 0.0, 0.0);
  }
  vec3 v = p / r;
  float theta = acos(v.z);
  float phi = atan(v.y, v.x);
  return vec3(r, theta, phi);
}

// TODO: Derive simpler closed formula from this or via quarternion
mat3 T_axisAngle(vec3 v, float rad) {
  vec3 rtp = T_cartesianToSpherical(v);
  mat3 P = T_rotate3(vec3(0.0, rtp[1], rtp[2]));
  return P * T_rotate3(vec3(0.0, 0.0, rad)) * inverse(P);
}

// TODO: this creates seams at uv discontinuity (u.x = 0.0, 1.0) when mipmap is used
vec2 T_texcoordLatLng(vec3 dir) {
  vec3 rtp = T_cartesianToSpherical(dir.zxy);
  float theta = rtp.y;
  float phi = rtp.z;

  // Reorient so that original image's midde row goes like (+z, -x, -z, +x, -z)
  return vec2(
      1.0 - (mod(phi, 2.0 * M_PI) / (2.0 * M_PI)),
      1.0 - theta / M_PI);
}

vec2 T_polarToCartesian(vec2 p) {
  return vec2(
    p.x * cos(p.y),
    p.x * sin(p.y));
}

// (Almost everywhere) constant Jacobian 2d-isotopy between square and disk by Shirly and Chiu
vec2 T_squareToDisk_polar(vec2 u) {
  // [0, 1]^2 -> [-1, 1]^2
  u = 2.0 * u - 1.0;

  // Flip around to the 1/8 part of square { (x, y) | x in [0, 1], y in [0, x] }
  vec2 sign_u = sign(u);
  vec2 abs_u = abs(u);
  bool swap_xy = abs_u.x < abs_u.y;
  vec2 eighth_u = !swap_xy ? abs_u : vec2(abs_u.y, abs_u.x);

  float radius = eighth_u.x;
  float phi = M_PI / 4.0 * eighth_u.y / eighth_u.x; // in [0, pi/4]

  // Flip back to the original part
  phi = !swap_xy ? phi : (M_PI / 2.0 - phi);       // in [0, pi/2]
  phi = 0 < sign_u.x ? phi : (M_PI - phi);         // in [0, pi]
  phi = 0 < sign_u.y ? phi : (2.0 * M_PI - phi);   // in [0, 2pi]

  return vec2(radius, phi);
}

vec2 T_squareToDisk(vec2 u) {
  return T_polarToCartesian(T_squareToDisk_polar(u));
}

// Extract 2d uniform distribution based on T_squareToDisk_polar
vec2 T_squareToDisk_polarUniform(vec2 u) {
  // Map to uniform on disk (but its polar coord [0, 1] x [0, 2pi] is not uniform)
  vec2 rp = T_squareToDisk_polar(u);
  float radius = rp[0];  // P(r) = 2r (i.e. F(r) = r^2)
  float phi = rp[1];     // P(phi) : uniform

  // Map to uniform on [0, 1]
  float u1 = radius * radius;
  return vec2(u1, phi / (2.0 * M_PI));
}
