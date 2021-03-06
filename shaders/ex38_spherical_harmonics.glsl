//
// Shade sphere by spherical harmonics
//

#include "common_v0.glsl"

const vec3 OZN = vec3(1.0, 0.0, -1.0);

float AA = 2.0;

// Ray intersection
float RAY_MAX_T = 100.0;

// Background color
vec3  SKY_COLOR_RANGE[2] = vec3[2](vec3(0.5, 0.75, 0.75), vec3(0.85, 0.95, 0.95));

// Camera
float CAMERA_YFOV = 60.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(1.0, 1.5, 2.0) * 2.0;
vec3  CAMERA_LOOKAT = vec3(0.0, 0.0, 0.0);
vec3  CAMERA_UP =     vec3(0.0, 1.0, 0.0);
float CAMERA_SCALE_TIME = 1.0 / 32.0;

// Misc container
struct SceneInfo {
  float t;  // signed distance, 1d ray coordinate, etc..
  float id; // id associated with state t
};

float SPHERE_RADIUS = 1.0;
vec3  SPHERE_CENTER = vec3(0.0);

bool Intersect_ray_sphere(vec3 o, vec3 v, vec3 c, float r, out float t_hit) {
  // assert |v| = 1
  float t = dot(c - o, v);
  if (t <= 0) return false;

  float l = distance(c, o + t * v);
  if (r < l) return false;

  float a = sqrt(r*r - l*l);  // l * tan(acos(r / l))
  t_hit = t - a;
  return true;
}

SceneInfo rayIntersect(vec3 orig, vec3 dir) {
  SceneInfo ret;
  ret.t = RAY_MAX_T;

  float t_hit;
  if (Intersect_ray_sphere(orig, dir, SPHERE_CENTER, SPHERE_RADIUS, t_hit)) {
    ret.t = t_hit;
  }
  return ret;
}

//
// Macro generated by misc/harmonic_polynomial/main.py
//
#define SH_LEGENDRE(_) \
  _((1.0/8.0)*sqrt(35)*(SH_SIN_THETA*(SH_SIN_THETA*SH_SIN_THETA))/sqrt(SH_PI)) \
  _(-1.0/8.0*sqrt(210)*SH_COS_THETA*SH_SIN_THETA*SH_SIN_THETA/sqrt(SH_PI)) \
  _((1.0/8.0)*(4*sqrt(21)*SH_SIN_THETA*(SH_COS_THETA*SH_COS_THETA) - sqrt(21)*SH_SIN_THETA*(SH_SIN_THETA*SH_SIN_THETA))/sqrt(SH_PI)) \
  _(-1.0/4.0*(-3*sqrt(7)*SH_COS_THETA*SH_SIN_THETA*SH_SIN_THETA + 2*sqrt(7)*(SH_COS_THETA*(SH_COS_THETA*SH_COS_THETA)))/sqrt(SH_PI)) \
  _(-1.0/8.0*(4*sqrt(21)*SH_SIN_THETA*(SH_COS_THETA*SH_COS_THETA) - sqrt(21)*SH_SIN_THETA*(SH_SIN_THETA*SH_SIN_THETA))/sqrt(SH_PI)) \
  _(-1.0/8.0*sqrt(210)*SH_COS_THETA*SH_SIN_THETA*SH_SIN_THETA/sqrt(SH_PI)) \
  _(-1.0/8.0*sqrt(35)*SH_SIN_THETA*(SH_SIN_THETA*SH_SIN_THETA)/sqrt(SH_PI))

vec3 colorSphericalHarmonics(float l, float m, float theta, float phi) {
  // assert l = 3
  // aseert |m| <= l

  #define SH_PI M_PI
  #define SH_SIN_THETA sin(theta)
  #define SH_COS_THETA cos(theta)
  #define FILL_SH_LEGENDRE(L) L,
  float[8] sh_legendre = float[8](
    SH_LEGENDRE(FILL_SH_LEGENDRE)
    0 // Make last empty entry for macro trick to work
  );
  #undef SH_PI
  #undef SH_SIN_THETA
  #undef SH_COS_THETA
  #undef FILL_SH_LEGENDRE

  float real_azimuthal = 0.5 + 0.5 * cos(m * phi);
  float tmp = sh_legendre[int(l) - int(m)] * real_azimuthal;
  float positive = max(+tmp, 0.0);
  float negative = max(-tmp, 0.0);
  return vec3(positive, negative, 0.0) * 2.0;
}

vec3 shadeSphericalHarmonics(vec3 p) {
  //
  // - [x] Macro generation
  // - [x] Visualization
  //   - positive/negative different color channel
  //   - multiply real part of azimuthal factor
  //   - [-] better tonemap/normalization (Legendre's maximum absolute value?)
  // - [x] Interpolation between different m
  //
  float theta = acos(p.y);
  float phi   = atan(p.x, p.z);

  float l = 3.0;
  float m = 2.0;
  vec2 t = iTime + vec2(0.0, 1.0);
  t = mod(t + l, 2.0 * l + 1.0) - l;
  float m1 = floor(t.x);
  float m2 = floor(t.y);
  float s = fract(t.x);
  vec3 c1 = colorSphericalHarmonics(l, m1, theta, phi);
  vec3 c2 = colorSphericalHarmonics(l, m2, theta, phi);
  return mix(c1, c2, smoothstep(0.0, 1.0, s));
}

vec3 shadeEnvironment(vec3 ray_orig, vec3 ray_dir) {
  float t = 0.5 + 0.5 * ray_dir.y; // \in [0, 1]
  t = smoothstep(0.0, 1.0, t);
  return mix(SKY_COLOR_RANGE[0], SKY_COLOR_RANGE[1], t);
}

vec3 singleSample(vec2 frag_coord, vec3 ray_orig, mat3 ray_xform) {
  // Setup camera ray
  vec3 ray_dir = normalize(ray_xform * vec3(frag_coord, 1.0));

  // Ray test
  SceneInfo info = rayIntersect(ray_orig, ray_dir);
  vec3 color;
  if (info.t < RAY_MAX_T) {
    vec3 p = ray_orig + info.t * ray_dir;
    color = shadeSphericalHarmonics(p);

  } else {
    color = shadeEnvironment(ray_orig, ray_dir);
  }
  return color;
}

mat4 getCameraTransform(vec4 mouse, vec2 resolution) {
  bool mouse_activated, mouse_down;
  vec2 last_click_pos, last_down_pos;
  getMouseState(mouse, mouse_activated, mouse_down, last_click_pos, last_down_pos);

  vec2 delta = OZN.yy;
  // delta.x += CAMERA_SCALE_TIME * iTime;
  if (mouse_activated && mouse_down) {
    delta += (last_down_pos - last_click_pos) / resolution;
  }
  return pivotTransform(CAMERA_LOC, CAMERA_LOOKAT, 2.0 * M_PI * delta);
}

float sampleGrid(vec2 p, vec2 dxdp, vec2 dydp, float line_width) {
  // assert line_width < 0.5
  float d2 = line_width;
  float d = 0.5 * line_width;

  // Original single sample formula
  // vec2 q = step(0.0, (0.5 - d) - abs(fract(p) - 0.5));
  // return 1.0 - q.x * q.y;

  // Integrate on approximate box pixel coverage
  vec2 l = abs(dxdp) + abs(dydp);
  vec2 p_min = p + 0.5 * l;
  vec2 p_max = p - 0.5 * l;
  vec2 integrals =
      + floor(p_max - d) * (1 - d2)
      - floor(p_min - d) * (1 - d2)
      + clamp(fract(p_max - d), 0.0, 1.0 - d2)
      - clamp(fract(p_min - d), 0.0, 1.0 - d2);
  vec2 avg_integrals = integrals / l;
  return 1.0 - avg_integrals.x * avg_integrals.y;
}

void closest_line_line(
    vec3 p1, vec3 v1, vec3 p2, vec3 v2,
    out float t1, out float t2) {
  vec3 u = p1 - p2;
  mat2x3 A = mat2x3(v1, -v2);
  mat3x2 AT = transpose(A);
  vec2 t = - inverse(AT * A) * AT * u;
  t1 = t.x;
  t2 = t.y;
}

float getCylinderCoverge(
    vec3 orig, vec3 dir, float width, float blur_width,
    vec3 ray_orig, vec3 ray_dir) {
  float t1, t2;
  closest_line_line(ray_orig, ray_dir, orig, dir, t1, t2);
  float l = distance(ray_orig + t1 * ray_dir, orig + t2 * dir);
  float fac = 1.0 - smoothstep(0.0, 1.0, (l - 0.5 * width) / blur_width + 0.5);
  return step(0.0, t1) * fac;
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // Setup coordinate system
  mat3 inv_view_xform = inverseViewTransform(CAMERA_YFOV, iResolution.xy);
  mat4 camera_xform = getCameraTransform(iMouse, iResolution.xy);
  vec3 ray_orig = vec3(camera_xform[3]);
  mat3 ray_xform = mat3(camera_xform) * mat3(OZN.xyy, OZN.yxy, -OZN.yyx) * inv_view_xform;

  // Averaging multisamples
  vec3 color = vec3(0.0);
  vec2 int_coord = floor(frag_coord);
  for (float i = 0.0; i < AA; i++) {
    for (float j = 0.0; j < AA; j++) {
      vec2 fract_coord = (0.5 + vec2(i, j) / 2.0) / AA;
      vec2 ms_frag_coord = int_coord + fract_coord;
      color += singleSample(ms_frag_coord, ray_orig, ray_xform);
    }
  }
  color /= (AA * AA);
  color = pow(color, vec3(1.0 / 2.2));

  {
    // grid
    vec3 normal = OZN.yxy;
    vec3 ray_dir = normalize(ray_xform * vec3(frag_coord, 1.0));
    float t = intersect_Line_Plane(ray_orig, ray_dir, vec3(0.0), normal);
    if (t > 0) {
      vec3 p = ray_orig + t * ray_dir;
      vec3 ray_dir_next_x = ray_dir + ray_xform[0];
      vec3 ray_dir_next_y = ray_dir + ray_xform[1];
      float tx = intersect_Line_Plane(ray_orig, ray_dir_next_x, p, normal);
      float ty = intersect_Line_Plane(ray_orig, ray_dir_next_y, p, normal);
      vec3 dxdp = ray_orig + tx * ray_dir_next_x - p;
      vec3 dydp = ray_orig + ty * ray_dir_next_y - p;

      float line_width = 0.03;
      float fac = sampleGrid(p.zx, dxdp.zx, dydp.zx, line_width);
      color = mix(color, vec3(1.0), 0.75 * fac);
    }

    // axes
    for (int i = 0; i < 3; i++) {
      vec3 v = vec3(0.0); v[i] = 1.0;
      float fac = getCylinderCoverge(OZN.yyy, v, 0.03, 0.01, ray_orig, ray_dir);
      color = mix(color, v, 0.5 * fac);
    }
  }
  frag_color = vec4(color, 1.0);
}
