//
// SDF Modifier/Op experiment
//

#include "common_v0.glsl"
#define oz vec2(1.0, 0.0)

float AA = 3.0;
bool  DEBUG_NORMAL = false;

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
vec3  SKY_COLOR_RANGE[2] = vec3[2](vec3(0.1), vec3(0.85, 0.9, 0.9));

// Misc
float CAMERA_YFOV = 30.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(1.0, 0.7, 2.0) * 8.0;
vec3  CAMERA_LOOKAT = vec3(0.0, 1.0, 0.0);
vec3  CAMERA_UP =     vec3(0.0, 1.0, 0.0);


//
// Sdf routines
//

float Sdf_sphere(vec3 p, float r) {
  return length(p) - r;
}

float Sdf_box(vec3 p, vec3 q) {
  vec3 sd3 = abs(p) - q;
  float m = max(max(sd3.x, sd3.y), sd3.z);
  return m < 0 ? m : length(max(sd3, vec3(0.0)));
}

float Sdf_lineSegment(vec3 p, vec3 v, float t0, float t1) {
  // assert |v| = 1
  float t = dot(p, v);
  t = clamp(t, t0, t1);
  return distance(p, t * v);
}

float Sdf2_disk(vec2 p, float r) {
  return length(p) - r;
}

float Sdf2_lineSegment(vec2 p, vec2 v, float t0, float t1) {
  // assert |v| = 1
  float t = dot(p, v);
  t = clamp(t, t0, t1);
  return distance(p, t * v);
}

vec2 SdfMod_revolution(vec3 p) {
  return vec2(length(p.xz), p.y);
}

vec3 SdfMod_repeat2d(vec3 p, vec2 XZ, out vec2 id) {
  // Wrap coordinates into [-X/2, -Z/2] x [X/2, Z/2]
  id = floor(p.xz / XZ + 0.5);
  p.xz = (fract(p.xz / XZ + 0.5) - 0.5) * XZ;
  return p;
}

vec3 SdfMod_repeat2dBounded(
    vec3 p, vec2 XZ, out vec2 id, vec2 n0_xz, vec2 n1_xz) {
  vec2 q = p.xz / XZ;
  vec2 qc = clamp(q, n0_xz, n1_xz);
  id = floor(q + 0.5);
  p.xz = ((fract(qc + 0.5) - 0.5) + (q - qc)) * XZ;
  return p;
}

vec3 SdfMod_instancingRegularPolygon(vec3 p, float n, out float id) {
  // Wrap coordinates into t \in [-pi/n, pi/n]
  // where t is cylindrical angle coordinates
  id = atan(p.x, p.z);
  float t = mod(id + 2.0 * M_PI, 2.0 * M_PI / n) - M_PI / n;
  p.zx = length(p.zx) * vec2(cos(t), sin(t));
  return p;
}

float SdfOp_extrude(float y, float sd_zx, float bound_y) {
  float sd_y = abs(y) - bound_y;
  float m = max(sd_zx, sd_y);
  return m < 0 ? m : length(max(vec2(sd_zx, sd_y), vec2(0.0)));
}

float SdfOp_deepen(float sd, float w) {
  return sd - w;
}

float SdfOp_ud(float sd) {
  return abs(sd);
}


//
// Scene definition
//

struct SceneInfo {
  float t;  // signed distance or ray 1d coordinate
  float id; // material associated with the data t
};

float kIdOtherMin = 10.0;

SceneInfo mergeSceneInfo(SceneInfo info, float t, float id) {
  info.id = info.t < t ? info.id : id;
  info.t  = info.t < t ? info.t  : t ;
  return info;
}

SceneInfo mainSdf(vec3 p) {
  SceneInfo ret;
  ret.t = FLT_MAX;
  {
    // Ground by repeating thin boxes
    vec2 id;
    vec2 XZ = 1.0 * oz.xx;
    float n = 3.0;
    vec3 q = SdfMod_repeat2dBounded(p, XZ, id, -n * oz.xx, n * oz.xx);
    float sd = Sdf_box(q, 0.42 * oz.xyx);
    sd = SdfOp_deepen(sd, 0.05);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__) + id.x + id.y * id.y);
  }
  {
    // Extrude
    vec3 q = (p - oz.yxy);
    float r = 2.0;
    float extrude = 0.5;
    float deepen = 0.1;
    float sd = Sdf2_disk(q.zx, r);
    sd = SdfOp_ud(sd); // circle's ud
    sd = SdfOp_extrude(q.y, sd, extrude);
    sd = SdfOp_deepen(sd, deepen);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // Revolution
    vec3 q = (p - 2.5 * oz.yxy);
    float deepen = 0.1;
    float sd = Sdf2_lineSegment(
        SdfMod_revolution(q), normalize(oz.xx), 0.0, 2.0);
    sd = SdfOp_deepen(sd, deepen);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // Regular polygon instanting
    float n = 20.0;
    float deepen = 0.05;
    float id;
    vec3 q = (p - 0.5 * oz.yxy);
    float sd =Sdf_lineSegment(
        SdfMod_instancingRegularPolygon(q, n, id),
        normalize(oz.yxx), 3.0, 4.0);
    sd = SdfOp_deepen(sd, deepen);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__) + id * 10.0);
  }
  {
    // Mobius band by regular polygon instanting
    // TODO:
    //   Actually this distance field is incorrect since
    //   SdfMod_instancingRegularPolygon assumes given sdf
    //   to be exact copy (i.e. not rotated one).
    float n = 128.0;
    float deepen = 0.05;
    float id;
    vec3 q1 = (p - 2.0 * oz.yxy);
    vec3 q2 = SdfMod_instancingRegularPolygon(q1, n, id);
    vec3 v = rotate3(vec3(0.5 * id, 0.0, 0.0)) * oz.yyx;
    float sd =Sdf_lineSegment(q2 - 3.0 * oz.yyx, v, -0.5, 0.5);
    sd = SdfOp_deepen(sd, deepen);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
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
  float d = RM_NORMAL_DELTA;
  float dx_sdf = mainSdf(p + d * oz.xyy).t - mainSdf(p - d * oz.xyy).t;
  float dy_sdf = mainSdf(p + d * oz.yxy).t - mainSdf(p - d * oz.yxy).t;
  float dz_sdf = mainSdf(p + d * oz.yyx).t - mainSdf(p - d * oz.yyx).t;
  return normalize(vec3(dx_sdf, dy_sdf, dz_sdf));
}

vec3 shadeSurface(vec3 p, vec3 ray_dir, float id) {
  vec3 base_color = MATERIAL_BASE_COLOR;
  if (id >= kIdOtherMin) {
    float t = id - kIdOtherMin;
    base_color = Quick_color(Quick_hash(t, 123456));
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
  float t = 0.5 + 0.5 * ray_dir.y; // \in [0, 1]
  t = smoothstep(0.0, 1.0, t);

  return mix(SKY_COLOR_RANGE[0], SKY_COLOR_RANGE[1], t);
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
      vec2 fract_coord = (1.0 + vec2(i, j) / 2.0) / AA;
      vec2 ms_frag_coord = int_coord + fract_coord;
      color += singleSample(ms_frag_coord, inv_view_xform, camera_xform);
    }
  }
  color /= (AA * AA);
  color = pow(color, vec3(1.0 / 2.2));
  frag_color = vec4(color, 1.0);
}
