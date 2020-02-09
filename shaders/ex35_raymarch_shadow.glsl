//
// Ray march shadow
//

#include "common_v0.glsl"
const vec3 OZN = vec3(1.0, 0.0, -1.0);

float AA = 2.0;
bool  DEBUG_NORMAL = false;

// Ray intersection
float RAY_MAX_T = 100.0;

// Ray march
int   RM_MAX_ITER = 100;
float RM_SURFACE_DISTANCE = 0.001;
float RM_NORMAL_DELTA = 0.001;

// Shading
vec3  LIGHT_DIR = normalize(vec3(-1.0, -1.0, -0.5));
vec3  LIGHT_COLOR = vec3(1.0, 1.0, 1.0);
vec3  PHONG_AMBIENT = vec3(0.05);
float PHONG_SPECULAR = 30.0;
float DIFFUSE_COEFF  = 0.8;
float SPECULAR_COEFF = 0.3;
vec3  SKY_COLOR_RANGE[2] = vec3[2](vec3(0.2), vec3(0.85, 0.9, 0.9));

// Camera
float CAMERA_YFOV = 60.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(1.0, 1.5, 2.0) * 6.0;
vec3  CAMERA_LOOKAT = vec3(0.0, 0.0, 0.0);
vec3  CAMERA_UP =     vec3(0.0, 1.0, 0.0);
float CAMERA_SCALE_TIME = 1.0 / 32.0;


//
// Sdf routines
//

float Sdf_sphere(vec3 p, float r) {
  return length(p) - r;
}

float Sdf_box(vec3 p, vec3 q) {
  vec3 sd3 = abs(p) - q;
  float m = max(max(sd3.x, sd3.y), sd3.z);
  return m < 0.0 ? m : length(max(sd3, vec3(0.0)));
}

float Sdf_circle(vec3 p, float r) {
  return length(vec2(length(p.zx) - r, p.y));
}

float Sdf_lineSegment(vec3 p, vec3 v, float t0, float t1) {
  // assert |v| = 1
  return distance(p, clamp(dot(p, v), t0, t1) * v);
}

// float SdfMod_regularPolygon() {
// }

//
// Scene definition
//

// Misc container
struct SceneInfo {
  float t;  // signed distance, 1d ray coordinate, etc..
  float id; // id associated with state t
};

float kIdGround = 0.0;
float kIdOtherMin = 10.0;

SceneInfo mergeSceneInfo(SceneInfo info, float t, float id) {
  info.id = info.t < t ? info.id : id;
  info.t  = info.t < t ? info.t  : t ;
  return info;
}

SceneInfo getSceneSdf(vec3 p) {
  SceneInfo ret;
  ret.t = RAY_MAX_T;
  {
    // Ground
    vec3 size = vec3(6.0, 0.001, 6.0);
    float sd = Sdf_box(p, size);
    ret = mergeSceneInfo(ret, sd, kIdGround);
  }
  {
    // Sphere
    vec3 loc = vec3(2.0, 1.4, 2.0);
    float r = 1.0;
    float sd = Sdf_sphere(p - loc, r);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // Box
    vec3 loc = vec3(-2.0, 1.4, 2.0);
    vec3 b = vec3(0.8);
    float ext = 0.1;
    float sd = Sdf_box(p - loc, b) - ext;
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // Torus
    vec3 loc = vec3(2.0, 1.4, -2.0);
    float r1 = 1.0;
    float r2 = 0.4;
    float sd = Sdf_circle(p - loc, r1) - r2;
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // Line
    vec3 loc = vec3(-2.0, 0.5, -2.0);
    vec3 v = OZN.yxy;
    float ext = 0.25;
    float sd = Sdf_lineSegment(p - loc, v, 0.0, 2.0) - ext;
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // Plane
    vec3 loc = vec3(0.0, 0.5, 0.0);
    vec3 size = vec3(1.0, 0.001, 1.0);
    float ext = 0.05;
    float sd = Sdf_box(p - loc, size) - ext;
    ret = mergeSceneInfo(ret, sd, kIdOtherMin);
  }
  return ret;
}


//
// Shading
//

SceneInfo rayIntersect(vec3 orig, vec3 dir);
SceneInfo rayMarch(vec3 orig, vec3 dir);
vec3 getNormal(vec3 p);

float sampleChecker(vec2 p, vec2 dxdp, vec2 dydp) {
  // Over-estimate pixel coverage by abs box
  vec2 b = abs(dxdp) + abs(dydp);

  // Integrate and take average
  vec2 q = sign(mod(p, 2.0) - 1.0);
  // return 0.5 - 0.5 * q.x * q.y; // separable single point formula

  vec2 v0 = mod(p - b / 2.0, 2.0);
  vec2 v1 = mod(p + b / 2.0, 2.0);
  vec2 avg_integrals = (abs(v1 - 1.0) - abs(v0 - 1.0)) / b;
  return 0.5 - 0.5 * avg_integrals.x * avg_integrals.y;
}

float getRayOcculusion(vec3 orig, vec3 dir) {
  float MIN_T = 0.01;
  SceneInfo info = rayIntersect(orig + MIN_T * dir, dir);
  if (info.t < RAY_MAX_T) { // i.e. hit
    return 0.0;
  }
  return 1.0;
}

float getSoftRayOcculusion(vec3 orig, vec3 dir) {
  float MIN_T = 0.01;
  float MAX_T = 10.0;
  float ud_occ = 1e30;
  float sd_last = 0.0;
  for (float t = MIN_T; t < MAX_T; ) {
    SceneInfo step = getSceneSdf(orig + t * dir);
    // Update only when ray is getting closer to scene surface,
    // which excludes ray origin surface itself
    if (step.t < sd_last) {
      ud_occ = min(ud_occ, step.t);
    }
    if (step.t < RM_SURFACE_DISTANCE) {
      break;
    }
    t += step.t;
    sd_last = step.t;
  }
  float SOFT_OCC_WIDTH = 0.3;
  return smoothstep(0.0, 1.0, ud_occ / SOFT_OCC_WIDTH);
}

// NOTE: this "inner softness" doesn't work when thin plane is occluder.
float getSoftRayOcculusion_v2(vec3 orig, vec3 dir) {
  float MIN_T = 0.01;
  float MAX_T = 10.0;
  float sd_occ = 1e30;
  float sd_last = getSceneSdf(orig + MIN_T * dir).t;
  for (float t = MIN_T + abs(sd_last); t < MAX_T; ) {
    SceneInfo step = getSceneSdf(orig + t * dir);

    // Update only when ray is getting closer to scene surface
    // which excludes ray origin surface itself
    if (step.t < sd_last) {
      sd_occ = min(sd_occ, step.t);
    }

    // Break only when ray is getting out from interior
    if (sd_last < step.t && sd_last < 0) {
      break;
    }

    // Skip by MIN_T when not much progress (e.g. when normal orthogonal to `dir`)
    if (abs(step.t - sd_last) < 0.1 * RM_SURFACE_DISTANCE) {
      t += MIN_T;
      sd_last = getSceneSdf(orig + MIN_T * dir).t;
      t += abs(sd_last);
      continue;
    }

    // Let ray go interior of surface when ray gets close enough to surface
    if (0.0 < step.t && step.t < RM_SURFACE_DISTANCE && RM_SURFACE_DISTANCE <= sd_last) {
      t += (sd_last + step.t) * sd_last / (sd_last - step.t);
      sd_last = -step.t;
      continue;
    }

    t += abs(step.t);
    sd_last = step.t;
  }
  float SOFT_OCC_WIDTH = 0.25;
  return smoothstep(0.0, 1.0, sd_occ / SOFT_OCC_WIDTH + 0.5);
}

vec3 shadeSurface(
    vec3 p, vec3 normal, vec3 ray_orig, vec3 ray_dir,
    vec3 dxdp, vec3 dydp, SceneInfo info) {
  if (DEBUG_NORMAL) {
    return (0.5 + 0.5 * normal);
  }

  vec3 base_color = vec3(1.0);
  if (info.id == kIdGround) {
    float fac = sampleChecker(p.zx, dxdp.zx, dydp.zx);
    base_color = OZN.yxx * mix(0.2, 1.2, fac);
  }
  if (info.id >= kIdOtherMin) {
    float t = info.id - kIdOtherMin;
    base_color = Quick_color(Quick_hash(t, 123456.0));
  }

  //
  // Lighting
  //
  vec3 N = normal;
  vec3 L = -LIGHT_DIR;
  vec3 V = -ray_dir;         // view vector
  vec3 H = normalize(V + L); // half vector
  vec3 R = - V + 2.0 * dot(N, V) * N;
  float LdotN = max(0.0, dot(L, N));
  float HdotN = max(0.0, dot(H, N));
  vec3 color = vec3(0.0);

  float light_occ = getSoftRayOcculusion(p, L);
  // float light_occ = getSoftRayOcculusion_v2(p, L);

  // [Debug]
  // return vec3(light_occ);

  // Phong's ambient
  color += PHONG_AMBIENT * base_color;

  // Lambertian diffuse
  color += light_occ * base_color * LIGHT_COLOR * LdotN  * DIFFUSE_COEFF;

  // Phong's specular
  color += light_occ * LIGHT_COLOR * pow(HdotN, PHONG_SPECULAR)   * SPECULAR_COEFF;
  return color;
}

vec3 shadeEnvironment(vec3 ray_orig, vec3 ray_dir) {
  float t = 0.5 + 0.5 * ray_dir.y; // \in [0, 1]
  t = smoothstep(0.0, 1.0, t);
  return mix(SKY_COLOR_RANGE[0], SKY_COLOR_RANGE[1], t);
}


//
// ray testing / ray march routines
//

vec3 getNormal(vec3 p) {
  // Regular tetrahedron from cube's 4 corners
  const mat4x3 A = mat4x3(OZN.xxx, OZN.zzx, OZN.xzz, OZN.zxz) / sqrt(3.0);
  const mat3x4 AT = transpose(A);
  const mat3x3 inv_A_AT = inverse(A * AT);
  const mat4x3 B = inv_A_AT * A;
  vec4 AT_G = vec4(
      getSceneSdf(p + RM_NORMAL_DELTA * A[0]).t,
      getSceneSdf(p + RM_NORMAL_DELTA * A[1]).t,
      getSceneSdf(p + RM_NORMAL_DELTA * A[2]).t,
      getSceneSdf(p + RM_NORMAL_DELTA * A[3]).t);
  return normalize(B * AT_G);
}

SceneInfo rayMarch(vec3 orig, vec3 dir) {
  SceneInfo result;
  result.t = RAY_MAX_T;

  float t = 0.0;
  for (int i = 0; i < RM_MAX_ITER; i++) {
    SceneInfo step = getSceneSdf(orig + t * dir);
    t += step.t;
    if (abs(step.t) < RM_SURFACE_DISTANCE) {
      result.t = t;
      result.id = step.id;
      break;
    }
    if (step.t < 0.0 || RAY_MAX_T <= t) {
      break;
    }
  }
  return result;
}

SceneInfo rayIntersect(vec3 orig, vec3 dir) {
  return rayMarch(orig, dir);
}

vec3 singleSample(vec2 frag_coord, mat3 inv_view_xform, mat4 camera_xform) {
  // Setup camera ray
  vec3 ray_orig = vec3(camera_xform[3]);
  mat3 ray_xform = mat3(camera_xform) * mat3(OZN.xyy, OZN.yxy, -OZN.yyx) * inv_view_xform;
  vec3 ray_dir = normalize(ray_xform * vec3(frag_coord, 1.0));

  // Ray test
  SceneInfo info = rayIntersect(ray_orig, ray_dir);
  vec3 color;
  if (info.t < RAY_MAX_T) {
    vec3 p = ray_orig + info.t * ray_dir;
    vec3 normal = getNormal(p);
    vec3 ray_dir_next_x = ray_xform * vec3(frag_coord + OZN.xy, 1.0);
    vec3 ray_dir_next_y = ray_xform * vec3(frag_coord + OZN.yx, 1.0);
    float tx = intersect_Line_Plane(ray_orig, ray_dir_next_x, p, normal);
    float ty = intersect_Line_Plane(ray_orig, ray_dir_next_y, p, normal);
    vec3 dxdp = ray_orig + tx * ray_dir_next_x - p;
    vec3 dydp = ray_orig + ty * ray_dir_next_y - p;
    color = shadeSurface(p, normal, ray_orig, ray_dir, dxdp, dydp, info);

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
  delta.x += CAMERA_SCALE_TIME * iTime;
  if (mouse_activated && mouse_down) {
    delta += (last_down_pos - last_click_pos) / resolution;
  }
  return pivotTransform(CAMERA_LOC, CAMERA_LOOKAT, 2.0 * M_PI * delta);
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
      vec2 fract_coord = (0.5 + vec2(i, j) / 2.0) / AA;
      vec2 ms_frag_coord = int_coord + fract_coord;
      color += singleSample(ms_frag_coord, inv_view_xform, camera_xform);
    }
  }
  color /= (AA * AA);
  color = pow(color, vec3(1.0 / 2.2));
  frag_color = vec4(color, 1.0);
}
