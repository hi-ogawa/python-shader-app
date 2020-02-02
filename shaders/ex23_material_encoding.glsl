//
// Scene material encoding
//

#include "common_v0.glsl"

float AA = 3.0;
bool  DEBUG_NORMAL = false;
bool  SHOW_COORDINATE = false;
const vec2 V10 = vec2(1.0, 0.0);

// Raymarch
int   RM_MAX_ITER = 100;
float RM_MAX_DISTANCE = 100.0;
const float RM_SURFACE_DISTANCE = 0.001;
float RM_NORMAL_DELTA = 0.001;

// Shading
vec3  LIGHT_DIR = normalize(vec3(-1.0, -1.0, -0.5));
vec3  LIGHT_COLOR = vec3(1.0, 1.0, 1.0);
vec3  PHONG_AMBIENT = vec3(0.03);
float PHONG_SPECULAR = 30.0;
vec3  MATERIAL_BASE_COLOR = vec3(0.0, 1.0, 1.0);
float DIFFUSE_COEFF  = 0.8;
float SPECULAR_COEFF = 0.3;

// Misc
float CAMERA_YFOV = 30.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(1.0, 0.5, 2.0) * 8.0;
vec3  CAMERA_LOOKAT = vec3(0.0, 0.0, 0.0);
vec3  CAMERA_UP =     vec3(0.0, 1.0, 0.0);

vec3  SPHERE_LOC = vec3(0.0, 1.0, 0.0);
float SPHERE_RADIUS = 1.0;

float LINE_BOUND = 8.0;
float LINE_WIDTH = 0.01;


float SDF_sphere(vec3 p, float r) {
  return length(p) - r;
}

// box with corner at (+-q.x, +-q.y, +-q.z)
// assume q.x, q.y, q.z > 0
float SDF_box(vec3 p, vec3 q) {
  vec3 sd3 = abs(p) - q;
  float m = max(max(sd3.x, sd3.y), sd3.z);
  return m < 0 ? m : length(max(sd3, vec3(0.0)));
}

float SDF_halfSpace(vec3 p, vec3 n) {
  // assert |n| = 1
  return dot(p, n);
}

float SDF_simplex(vec3 p) {
  // TODO: not exact around when point is not orthgonal to any plane
  float t = SDF_halfSpace(p - V10.xyy, normalize(vec3(1.0)));
  // t < 0.0 ? t : ((??))
  vec3 sd3 = -p;
  return max(max(t, sd3.x), max(sd3.y, sd3.z));
}

// line segment passing origin { t v | t \in [t0, t1] }
float SDF2_lineSegment(vec2 p, vec2 v, float t0, float t1) {
  // assert |v| = 1
  float t = dot(p, v);
  float tb = clamp(t, t0, t1);
  return distance(p, tb * v);
}

// Special case of below SDF2_regularNGon
float SDF2_regularTriangle(vec2 p) {
  // Wrap plane by cyclic group 3
  float t = atan(p.y, p.x) + M_PI;     // in [0, 2pi]
  float s = mod(t, 2.0 * M_PI / 3.0) - M_PI / 3.0;  // in [-pi/3, pi/3]
  p = length(p) * vec2(cos(s), sin(s));

  // SDF on this wrapped region
  vec2 q = vec2(cos(M_PI / 3.0), sin(M_PI / 3.0));
  float sd = p.x - q.x;
  float d = SDF2_lineSegment(p - vec2(q.x, 0.0), V10.yx, -q.y, q.y);
  return sd < 0.0 ? sd : d;
}

float SDF2_regularPolygon(vec2 p, float n) {
  // Wrap plane by cyclic group n
  float t = atan(p.y, p.x) + M_PI;     // in [0, 2pi]
  float s = mod(t, 2.0 * M_PI / n) - M_PI / n;  // in [-pi/n, pi/n]
  p = length(p) * vec2(cos(s), sin(s));

  // SDF on this wrapped region
  vec2 q = vec2(cos(M_PI / n), sin(M_PI / n));
  float sd = p.x - q.x;
  float d = SDF2_lineSegment(p - vec2(q.x, 0.0), V10.yx, -q.y, q.y);
  return sd < 0.0 ? sd : d;
}

float SDF_lineSegment(vec3 p, vec3 v, float t0, float t1) {
  // assert |v| = 1
  float t = dot(p, v);
  float tb = clamp(t, t0, t1);
  return distance(p, tb * v);
}

vec2 baryCoordTriangle(vec3 p, vec3 u1, vec3 u2) {
  // Barycentric coord (p = s * u1 + t * u2)
  // assert - |u1|, |u2| = 1
  //        - u1, u2: linear indep.
  //        - p \in span{u1, u2}
  mat2x3 A = mat2x3(u1, u2);
  mat3x2 AT = transpose(A);
  vec2 st = inverse(AT * A) * AT * p;
  return st;
}

float SDF_Line(vec3 p, vec3 v) {
  // assert |v| = 1
  float t = dot(p, v);
  return distance(p, t * v);
}

float SDF_triangle(vec3 p, vec3 v1, vec3 v2, vec3 v3) {
  // Striaght-forward implementation of distance to triangle
  vec3 u1 = v2 - v1;
  vec3 u2 = v3 - v2;
  vec3 u3 = v1 - v3;
  float u1_l = length(u1);
  float u2_l = length(u2);
  float u3_l = length(u3);
  vec3 u1_n = u1 / u1_l;
  vec3 u2_n = u2 / u2_l;
  vec3 u3_n = u3 / u3_l;
  vec3 n = normalize(cross(u1_n, -u3_n));

  // Derive distance on plane and its orthogonal direction
  float ud_xy = 0.0, sd_z = 0.0;

  // Project p onto the plane where triangle lives
  sd_z = dot(p - v1, n);
  vec3 q = p - sd_z * n;
  vec2 uv = baryCoordTriangle(q - v1, u1_n, -u3_n)
            / vec2(u1_l, u3_l);

  float t1 = dot(q - v1, u1_n) / u1_l;
  float t2 = dot(q - v2, u2_n) / u2_l;
  float t3 = dot(q - v3, u3_n) / u3_l;

  // Cases:
  // 1. inside of triangle
  if (0.0 < uv.x && 0.0 < uv.y && uv.x + uv.y < 1.0) {
    ud_xy = 0.0;
  } else
  // 2. closest to some vertex
  if (t1 < 0.0 && 1.0 < t3) {
    ud_xy = distance(q, v1);
  } else
  if (t2 < 0.0 && 1.0 < t1) {
    ud_xy = distance(q, v2);
  } else
  if (t3 < 0.0 && 1.0 < t2) {
    ud_xy = distance(q, v3);
  } else
  // 3. closest to some edge
  if (        0.0 < uv.x && uv.x + uv.y < 1.0) {
    ud_xy = SDF_Line(q - v1, u1_n);
  } else
  if (        0.0 < uv.y &&         0.0 < uv.x) {
    ud_xy = SDF_Line(q - v2, u2_n);
  } else
  if (uv.x + uv.y < 1.0  &&         0.0 < uv.y) {
    ud_xy = SDF_Line(q - v3, u3_n);
  }

  return length(vec2(ud_xy, sd_z));
}

float SDF_octahedron(vec3 p) {
  // Wrap to 1/8 of space (i.e. octahedral symmetry)
  p = abs(p);

  // SDF on this space
  float sd = SDF_halfSpace(p - V10.yyx, normalize(vec3(1.0)));
  return sd < 0.0 ? sd : SDF_triangle(p, V10.xyy, V10.yxy, V10.yyx);
}

float SDF_pyramid(vec3 p, float h) {
  // Cylindrical coordinate (around y-axis)
  float r = length(p.xz);
  float t = atan(p.x, p.z);

  // Wrap to 1/3 of space (i.e. 3 cyclic group around y axis)
  float a = 2.0 * M_PI / 3.0;
  t = mod(t, a);
  p = vec3(r * sin(t), p.y, r * cos(t));

  // SDF on this space
  vec3 v1 = V10.yyx;
  vec3 v2 = vec3(sin(a), 0.0, cos(a));
  vec3 v3 = vec3(0.0, h, 0.0);
  vec3 n = normalize(cross(v2 - v1, v3 - v1));
  float sd1 = dot(p - v1, n);
  float sd2 = dot(p.zx - v1.zx, n.zx);
  float sd3 = -p.y;
  float ud4 = SDF_triangle(p, v1, v2, v3);

  // Cases:
  // 1. interior
  if (sd1 < 0 && sd3 < 0) {
    return max(sd1, sd3);
  }
  // 2. below the bottom triangle
  if (sd1 < 0 && sd3 >= 0.0 && sd2 < 0.0) {
    return sd3;
  }
  // 3. other case
  return ud4;
}

float SDF_circle(vec3 p, float r) {
  return length(vec2(length(p.xz) - r, p.y));
}

vec3 SDF_MOD_repeat1d_bounded(vec3 p, vec3 v, float t0, float t1) {
  float t = dot(p, v);
  float tc = clamp(t, t0, t1);
  float s = fract(tc + 0.5) - 0.5 + (t - tc);
  return p + (s - t) * v;
}

vec3 SDF_MOD_mirror(vec3 p, vec3 n) {
  // assert |n| = 1
  // assert SDF_<primitive>(p) > 0 for p s.t. dot(p, v) < 0
  //       (i.e. primitive is inside of half plane)
  float t = dot(p, n);
  return p + (abs(t) - t) * n;
}

float SDF_OP_extrude(float sd_zx, float y, float bound_y) {
  float sd_y = abs(y) - bound_y;
  float m = max(sd_zx, sd_y);
  return m < 0 ? m : length(max(vec2(sd_zx, sd_y), vec2(0.0)));
}

float SDF_checker(vec3 p, out bool odd) {
  odd = mod(floor(p.x) + floor(p.z), 2.0) != 0.0;
  return abs(p.y);
}

struct SceneInfo {
  float t;  // signed distance or ray 1d coordinate
  float id; // material associated with the data t
};

float kIdCheckerOdd = 0.0;
float kIdCheckerEven = 0.1;
float kIdCoordinate = 1.0;
float kIdOtherMin = 2.0;

SceneInfo mergeSceneInfo(SceneInfo info, float t, float id) {
  info.id = info.t < t ? info.id : id;
  info.t  = info.t < t ? info.t  : t ;
  return info;
}

SceneInfo mainSdf(vec3 p) {
  SceneInfo ret;
  ret.t = FLT_MAX;
  {
    // Sphere
    float sd_sphere = SDF_sphere(p - SPHERE_LOC, SPHERE_RADIUS);
    ret = mergeSceneInfo(ret, sd_sphere, kIdOtherMin + float(__LINE__));
  }
  {
    // Torus as thick circle
    float r1 = 2.0, r2 = 0.5;
    float ud_circle = SDF_circle(p - SPHERE_LOC, r1);
    ret = mergeSceneInfo(ret, ud_circle - r2, kIdOtherMin + float(__LINE__));
  }
  {
    // Simplices via mirroring
    vec3 loc_box = vec3(3.0, 0.7, 3.0);
    vec3 mod_p = SDF_MOD_mirror(SDF_MOD_mirror(p, V10.yyx), V10.xyy);
    float sd = SDF_simplex(mod_p - loc_box);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // Regular Triangle
    vec3 loc = 3.0 * V10.yxy;
    vec3 q = p - loc;
    float y_bound = 0.5;
    float sd = SDF_OP_extrude(SDF2_regularTriangle(q.zx), q.y, y_bound);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // Arbitrary Triangle
    {
      // TODO: seems there's a bug e.g.
      vec3 OZN = vec3(1.0, 0.0, -1.0);
      float depth = 0.1;
      float sd = SDF_triangle(p, OZN.yyy, OZN.xxz, OZN.zxx) - depth;
      // ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
    }
    vec3 loc = 3.0 * V10.xyy;
    vec3 q = p - loc;
    float sd = SDF_triangle(q, V10.yyx, V10.xyy, V10.yxy) - 0.08;
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + 1.5 * float(__LINE__));
  }
  {
    // Pyramid
    vec3 loc = 2.0 * V10.yxx;
    vec3 q = p - loc;
    float sd = SDF_pyramid(q, 2.0);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // Regular polygon
    vec3 loc = -1.0 * V10.yxy;
    vec3 q = p - loc;
    float y_bound = 0.5;
    float sd = SDF_OP_extrude(SDF2_regularPolygon(q.zx, 6.0), q.y, y_bound);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // octahedron
    vec3 loc = vec3(1.0, 1.0, 3.0);
    vec3 q = p - loc;
    float sd = SDF_octahedron(q);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  if (SHOW_COORDINATE || true) {
    // Coordinate system
    float B = LINE_BOUND;
    float W = LINE_WIDTH;

    // Y axis
    float ud_y = SDF_lineSegment(p, vec3(0.0, 1.0, 0.0), -B, B);
    ret = mergeSceneInfo(ret, ud_y - W, kIdCoordinate);

    // XZ grid plane
    float ud_zs_along_x = SDF_lineSegment(
        SDF_MOD_repeat1d_bounded(p, vec3(1.0, 0.0, 0.0), -B, B),
        vec3(0.0, 0.0, 1.0), - B - 0.5, B + 0.5);
    ret = mergeSceneInfo(ret, ud_zs_along_x - W, kIdCoordinate);

    float ud_xs_along_z = SDF_lineSegment(
        SDF_MOD_repeat1d_bounded(p, vec3(0.0, 0.0, 1.0), -B, B),
        vec3(1.0, 0.0, 0.0), - B - 0.5, B + 0.5);
    ret = mergeSceneInfo(ret, ud_xs_along_z - W, kIdCoordinate);
  } else {
    // Checker ground
    bool odd;
    float ground_y = 0.05;
    float ud_plane = SDF_checker(p + ground_y, odd);
    // ret = mergeSceneInfo(ret, ud_plane - ground_y, odd ? kIdCheckerOdd : kIdCheckerEven);
  }
  return ret;
}

SceneInfo rayMarch(vec3 orig, vec3 dir) {
  SceneInfo no_hit;
  no_hit.t = RM_MAX_DISTANCE;

  float t = 0.0;
  for (int i = 0; i < RM_MAX_ITER; i++) {
    SceneInfo res = mainSdf(orig + t * dir);
    t += res.t;
    if (abs(res.t) < RM_SURFACE_DISTANCE) {
      res.t = t;
      return res;
    }
    if (res.t < 0.0  || RM_MAX_DISTANCE <= t) {
      return no_hit;
    }
  }
  return no_hit;
}


// Approximate <face normal> = grad(SDF) by finite difference.
vec3 getNormal(vec3 p) {
  vec2 v10 = vec2(1.0, 0.0);
  float d = RM_NORMAL_DELTA;
  float dx_sdf = mainSdf(p + d * v10.xyy).t - mainSdf(p - d * v10.xyy).t;
  float dy_sdf = mainSdf(p + d * v10.yxy).t - mainSdf(p - d * v10.yxy).t;
  float dz_sdf = mainSdf(p + d * v10.yyx).t - mainSdf(p - d * v10.yyx).t;
  return normalize(vec3(dx_sdf, dy_sdf, dz_sdf));
}

vec3 shadeSurface(vec3 p, vec3 ray_dir, float id) {
  if (id == kIdCoordinate)
    return vec3(0.7);

  vec3 base_color =
      id == kIdCheckerEven ? vec3(0.3) :
      id == kIdCheckerOdd  ? vec3(0.8) :
                             MATERIAL_BASE_COLOR;

  if (id >= kIdOtherMin) {
    float t = id - kIdOtherMin;
    float hash = fract(sin(t * 123456) * 123456);
    vec3 rgb; {
      float t = hash;
      rgb = 0.5 + 0.5 * cos(2.0 * M_PI * (t - vec3(0.0, 1.0, 2.0) / 3.0));
      rgb = smoothstep(vec3(-0.1), vec3(0.9), rgb);
    }
    base_color = rgb;
  }

  // Shade hit surface
  vec3 normal = getNormal(p);

  // Lighting
  vec3 N = normal;
  vec3 L = -LIGHT_DIR;
  vec3 V = -ray_dir;         // view vector
  vec3 H = normalize(V + L); // half vector

  float LdotN = max(0.0, dot(normal, L));
  float HdotN = max(0.0, dot(H, N));

  vec3 color = vec3(0.0);

  // Phong's ambient
  color += PHONG_AMBIENT;

  // Lambertian diffuse
  color += base_color * LIGHT_COLOR * LdotN  * DIFFUSE_COEFF;

  // Phong's specular
  color += LIGHT_COLOR * pow(HdotN, PHONG_SPECULAR)   * SPECULAR_COEFF;

  // [Debug] normal
  if (DEBUG_NORMAL) {
    color = (0.5 + 0.5 * normal);
  }

  return color;
}

vec3 shadeEnvironment(vec3 ray_dir) {
  // Manual tweak
  float t = 0.5 + 0.5 * ray_dir.y; // \in [0, 1]
  t = smoothstep(0.0, 1.0, t);
  vec3 environment = mix(vec3(0.1), vec3(0.85, 0.9, 0.9), t);
  return environment;
}

vec3 singleSample(vec2 frag_coord, mat3 inv_view_xform, mat4 camera_xform) {
  // Setup camera ray
  vec3 ray_orig = vec3(camera_xform[3]);
  vec3 ray_dir; {
    vec2 uv = vec2(inv_view_xform * vec3(frag_coord, 1.0));
    vec3 ray_pos = mat3(camera_xform) * vec3(uv, -1.0);
    ray_dir = normalize(ray_pos);
  }

  // Ray test
  vec3 color = vec3(0.0);
  SceneInfo info = rayMarch(ray_orig, ray_dir);
  if (info.t < RM_MAX_DISTANCE) {

    // Shade hit surface
    vec3 p = ray_orig + info.t * ray_dir;
    color = shadeSurface(p, ray_dir, info.id);
  } else {

    // Otherwise draw sky-ish background
    color = shadeEnvironment(ray_dir);
  }
  return color;
}

mat4 getCameraTransform(vec4 mouse, vec2 resolution) {
  bool mouse_activated, mouse_down;
  vec2 last_click_pos, last_down_pos;
  getMouseState(mouse, mouse_activated, mouse_down, last_click_pos, last_down_pos);

  if (!(mouse_activated && mouse_down)) {
    return lookatTransform(CAMERA_LOC, CAMERA_LOOKAT, CAMERA_UP);
  }

  vec2 delta = 2.0 * M_PI * (last_down_pos - last_click_pos) / resolution;

  // Compute "origin-pivot" camera xform in two steps
  // - horizontal move
  vec3 roty = vec3(0.0, -delta.x, 0.0);
  vec3 camera_loc = rotate3(roty) * CAMERA_LOC;
  mat4 camera_xform_tmp = lookatTransform(camera_loc, CAMERA_LOOKAT, CAMERA_UP);

  // - vertical move
  vec3 rotx_axis = vec3(camera_xform_tmp[0]);
  float rotx_angle = delta.y;
  mat3 rotx = axisAngleTransform(rotx_axis, rotx_angle);
  mat4 camera_xform = mat4(rotx) * camera_xform_tmp;

  return camera_xform;
}


//
// Main
//

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // Setup coordinate system
  mat3 inv_view_xform = inverseViewTransform(CAMERA_YFOV, iResolution.xy);
  mat4 camera_xform = getCameraTransform(iMouse, iResolution.xy);

  // Averaging multisamples
  vec3 color = vec3(0.0);
  vec2 int_coord = floor(frag_coord);
  for (float i = 0.0; i < AA; i++) {
    for (float j = 0.0; j < AA; j++) {
      vec2 fract_coord = (0.5 + vec2(i, j) / 2.0) / AA;
      vec2 ms_frag_coord = int_coord + fract_coord;
      color += singleSample(ms_frag_coord, inv_view_xform, camera_xform);
    }
  }
  color /= (AA * AA);
  color = pow(color, vec3(1.0 / 2.2));
  frag_color = vec4(color, 1.0);
}
