//
// Simple scene to experiment with shading
// - [x] Sphere at the origin
// - [x] Axis/Grid (bounded)
// - [x] Camera control
// - [x] shading
//   - [x] Lambertian diffuse
//     - [x] Sun light source
//   - [x] Gamma correction
//   - [x] Phong's specular and ambient
// - [x] simple sky environment
//

#include "common_v0.glsl"

float AA = 3.0;
bool  DEBUG_NORMAL = false;

// Raymarch
int   RM_MAX_ITER = 100;
float RM_MAX_DISTANCE = 100.0;
const float RM_SURFACE_DISTANCE = 0.0005;
float RM_NORMAL_DELTA = 0.0001;

// Shading
vec3  LIGHT_DIR = normalize(vec3(-1.0, -1.0, 0.0));
vec3  LIGHT_COLOR = vec3(1.0, 1.0, 1.0);
vec3  PHONG_AMBIENT = vec3(0.03);
float PHONG_SPECULAR = 30.0;
vec3  MATERIAL_BASE_COLOR = vec3(0.0, 1.0, 1.0);
float DIFFUSE_COEFF  = 0.8;
float SPECULAR_COEFF = 0.3;

// Misc
float CAMERA_YFOV = 30.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(1.0, 0.5, 2.0) * 8.0;
vec3  CAMERA_LOOKAT = vec3(0.0);
vec3  CAMERA_UP =     vec3(0.0, 1.0, 0.0);

vec3  SPHERE_LOC = vec3(0.0, 0.0, 0.0);
float SPHERE_RADIUS = 1.4;

float LINE_BOUND = 8.0;
float LINE_WIDTH = 0.015;


float SDF_sphere(vec3 p, vec3 c, float r) {
  return length(p - c) - r;
}

float SDF_lineSegment(vec3 p, vec3 v, float t0, float t1) {
  // assert |v| = 1
  float t = dot(p, v);
  float tb = clamp(t, t0, t1);
  return distance(p, tb * v);
}

vec3 SDF_MOD_repeat1d(vec3 p, vec3 v) {
  // assert |v| = 1
  // assert SDF_<primitive>(p) > 0 for p s.t. |dot(p, v)| > 0.5 (i.e. bounded)
  float t = dot(p, v);
  float s = fract(t + 0.5) - 0.5;
  return p + (s - t) * v;
}

vec3 SDF_MOD_repeat1d_bounded(vec3 p, vec3 v, float t0, float t1) {
  // assert same condition as SDF_MOD_repeat1d
  float t = dot(p, v);
  float tc = clamp(t, t0, t1);
  float s = fract(tc + 0.5) - 0.5 + (t - tc);
  return p + (s - t) * v;
}

float mainSdf(vec3 p) {
  float sd = FLT_MAX;

  // Sphere
  {
    float sd_sphere = SDF_sphere(p, SPHERE_LOC, SPHERE_RADIUS);
    sd = min(sd, sd_sphere);
  }

  // Coordinate system
  {
    float B = LINE_BOUND;

    // Y axis
    float ud_y = SDF_lineSegment(p, vec3(0.0, 1.0, 0.0), -B, B);
    sd = min(sd, ud_y - LINE_WIDTH);

    // XZ grid plane
    float ud_zs_along_x = SDF_lineSegment(
        SDF_MOD_repeat1d_bounded(p, vec3(1.0, 0.0, 0.0), -B, B),
        vec3(0.0, 0.0, 1.0), - B - 0.5, B + 0.5);
    sd = min(sd, ud_zs_along_x - LINE_WIDTH);

    float ud_xs_along_z = SDF_lineSegment(
        SDF_MOD_repeat1d_bounded(p, vec3(0.0, 0.0, 1.0), -B, B),
        vec3(1.0, 0.0, 0.0), - B - 0.5, B + 0.5);
    sd = min(sd, ud_xs_along_z - LINE_WIDTH);
  }

  return sd;
}

float rayMarch(vec3 orig, vec3 dir) {
  float t = 0.0;
  for (int i = 0; i < RM_MAX_ITER; i++) {
    float sd = mainSdf(orig + t * dir);
    t += sd;
    if (sd < 0.0 || t >= RM_MAX_DISTANCE) {
      return RM_MAX_DISTANCE;
    }
    if (sd < RM_SURFACE_DISTANCE) {
      return t;
    }
  }
  return RM_MAX_DISTANCE;
}


//
// Main
//

// Approximate <face normal> = grad(SDF) by finite difference.
vec3 getNormal(vec3 p) {
  vec2 v10 = vec2(1.0, 0.0);
  float d = RM_NORMAL_DELTA;
  float dx_sdf = mainSdf(p + d * v10.xyy) - mainSdf(p - d * v10.xyy);
  float dy_sdf = mainSdf(p + d * v10.yxy) - mainSdf(p - d * v10.yxy);
  float dz_sdf = mainSdf(p + d * v10.yyx) - mainSdf(p - d * v10.yyx);
  return normalize(vec3(dx_sdf, dy_sdf, dz_sdf));
}

vec3 singleSample(vec2 frag_coord, mat3 inv_view_xform, mat4 camera_xform) {
  // Setup camera ray
  vec3 ray_orig = vec3(camera_xform[3]);
  vec3 ray_dir; {
    vec2 uv = vec2(inv_view_xform * vec3(frag_coord, 1.0));
    vec3 ray_pos = mat3(camera_xform) * vec3(uv, -1.0);
    ray_dir = normalize(ray_pos);
  }

  // RayMarch scene
  vec3 color = vec3(0.0);
  float d = rayMarch(ray_orig, ray_dir);
  if (d < RM_MAX_DISTANCE) {
    vec3 p = ray_orig + d * ray_dir;
    vec3 normal = getNormal(p);

    // Lighting
    vec3 N = normal;
    vec3 L = -LIGHT_DIR;
    vec3 V = -ray_dir;         // view vector
    vec3 H = normalize(V + L); // half vector

    float LdotN = max(0.0, dot(normal, L));
    float HdotN = max(0.0, dot(H, N));

    // Phong's ambient
    color += PHONG_AMBIENT;

    // Lambertian diffuse
    color += MATERIAL_BASE_COLOR * LIGHT_COLOR * LdotN  * DIFFUSE_COEFF;

    // Phong's specular
    color += LIGHT_COLOR * pow(HdotN, PHONG_SPECULAR)   * SPECULAR_COEFF;

    // [Debug] normal
    if (DEBUG_NORMAL) {
      color = (0.5 + 0.5 * normal);
    }
  } else {
    vec3 environment; {
      // Manual tweak
      float t = 0.5 + 0.5 * ray_dir.y; // \in [0, 1]
      t = smoothstep(0.0, 1.0, t);
      environment = mix(vec3(0.1), vec3(0.85, 0.9, 0.9), t);
    }
    color = environment;
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

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // Setup coordinate system
  mat3 inv_view_xform = inverseViewTransform(CAMERA_YFOV, iResolution.xy);
  mat4 camera_xform = getCameraTransform(iMouse, iResolution.xy);

  // Averaging multisamples
  vec3 color = vec3(0.0);
  vec2 int_coord = floor(frag_coord);
  for (float i = 0.0; i < AA; i++) {
    for (float j = 0.0; j < AA; j++) {
      vec2 fract_coord = (1.0 + vec2(i, j) / 2.0) / AA;
      vec2 ms_frag_coord = int_coord + fract_coord;
      color += singleSample(ms_frag_coord, inv_view_xform, camera_xform);
    }
  }
  color /= (AA * AA);
  color = pow(color, vec3(1.0 / 2.2));
  frag_color = vec4(color, 1.0);
}
