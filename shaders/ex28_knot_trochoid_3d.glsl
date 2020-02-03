//
// Knotted trochoid in 3D (cf. ex15_knot_trochoid.glsl)
//

#include "common_v0.glsl"
const vec3 OZN = vec3(1.0, 0.0, -1.0);

float AA = 1.0;
bool DEBUG_NORMAL = false;

// Ray intersection
float RAY_MAX_T = 100.0;

// Ray march
int   RM_MAX_ITER = 100;
float RM_SURFACE_DISTANCE = 0.001;
float RM_NORMAL_DELTA = 0.001;

// Shading
vec3  LIGHT_DIR = normalize(vec3(-1.0, -1.0, -0.5));
vec3  LIGHT_COLOR = vec3(1.0, 1.0, 1.0);
vec3  PHONG_AMBIENT = vec3(0.03);
float PHONG_SPECULAR = 30.0;
float DIFFUSE_COEFF  = 0.8;
float SPECULAR_COEFF = 0.3;
vec3  SKY_COLOR_RANGE[2] = vec3[2](vec3(0.2), vec3(0.85, 0.9, 0.9));

// Camera
float CAMERA_YFOV = 30.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(1.0, 0.5, 2.0) * 7.0;
vec3  CAMERA_LOOKAT = vec3(0.0, 0.0, 0.0);
vec3  CAMERA_UP =     vec3(0.0, 1.0, 0.0);
float CAMERA_SCALE_TIME = 1.0 / 32.0;

// Trochoid
const float kEpi = 0.0;
const float kHyper = 1.0;


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

float Sdf_lineSegment(vec3 p, vec3 v, float t0, float t1) {
  // assert |v| = 1
  float t = dot(p, v);
  float tb = clamp(t, t0, t1);
  return distance(p, tb * v);
}

vec2 SdfMod_revolution(vec3 p) {
  return vec2(length(p.xz), p.y);
}

float SdfOp_extrude(float y, float sd_zx, float bound_y) {
  float sd_y = abs(y) - bound_y;
  float m = max(sd_zx, sd_y);
  return m < 0.0 ? m : length(max(vec2(sd_zx, sd_y), vec2(0.0)));
}

float SdfOp_deepen(float sd, float w) {
  return sd - w;
}

float SdfOp_ud(float sd) {
  return abs(sd);
}


vec3 knottedTrochoidPoint(
    float t, float r1, float r2, float r3,
    float type, float scale_z) {
  float n = r1 / r2;
  vec3 q;
  if (type == kHyper) {
    q = vec3(
      // usual hyper-trochoid formula
      (r1 - r2) * cos(t) + r3 * cos((1 - n) * t),
      (r1 - r2) * sin(t) + r3 * sin((1 - n) * t),
      // knot by waving z coord along symmetry
      sin(n * t) * scale_z);
  }
  if (type == kEpi) {
    q = vec3(
      // usual epi-trochoid formula
      (r1 + r2) * cos(t) + r3 * cos((1.0 + n) * t - M_PI),
      (r1 + r2) * sin(t) + r3 * sin((1.0 + n) * t - M_PI),
      // knot by waving z coord along symmetry
      sin(n * t) * scale_z);
  }
  return q;
}

float Sdf_knottedTrochoid(
    vec3 p, float type, float knotness,
    float num_symmetry, float num_segments,
    float scale_z, bool point) {

  // Take care reparameterization and normalize overall size to about [-1, 1]^2
  float r1 = 1.0;
  float r2 = 1.0 / num_symmetry;
  float r3, size; {
    if (type == kHyper) {
      r3 = (1.0 - knotness) * r2 + knotness * (r1 - r2);
      size = r1 - r2 + r3;
    }
    if (type == kEpi) {
      r3 = (1.0 - knotness) * r2 + knotness * (r1 + r2);
      size = r1 + r2 + r3;
    }
  }
  r1 /= size; r2 /= size; r3 /= size;

  float min_distance = 1000.0;
  vec3 q1, q2;
  q1 = knottedTrochoidPoint(0.0, r1, r2, r3, type, scale_z);
  for (float i = 1.0; i < num_segments / num_symmetry + 1.0; i++) {
    float t = 2.0 * M_PI * i / num_segments;
    q2 = knottedTrochoidPoint(t, r1, r2, r3, type, scale_z);
    vec3  v = q2 - q1;
    float vl = length(v);
    vec3  vn = v / vl;

    // Optimize loop by moving point p to symmetric parts
    for (float j = 0.0; j < num_symmetry; j++) {
      float s = 2.0 * M_PI * j / num_symmetry;
      mat2 rot = mat2(cos(s), sin(s), -sin(s), cos(s));
      vec3 p_rot = vec3(rot * p.xy, p.z);
      float ud = point
        ? distance(p_rot, q1)
        : Sdf_lineSegment(p_rot - q1, vn, 0.0, vl);
      min_distance = min(min_distance, ud);
    }
    q1 = q2;
  }
  return min_distance;
}


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
    vec3 size = vec3(3.0, 1.0, 3.0) ;
    vec3 loc  = - vec3(0.0, size.y, 0.0);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdGround);
  }
  {
    mat3 rot = rotate3(- 0.5 * M_PI * OZN.zyy);
    vec3 loc = 1.4 * OZN.yxy;
    float scale = 3.0;
    vec3 q = rot * (p - loc) / scale;
    float num_symmetry = 3.0;
    float knotness = 2.5;
    float num_segments = 50.0;
    float scale_z = 1.0 / 3.0;
    bool point = false;
    float sd = Sdf_knottedTrochoid(
        q, kHyper, knotness, num_symmetry,
        num_segments, scale_z, point) * scale;
    float depth = 0.15;
    sd = SdfOp_deepen(sd, depth);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  return ret;
}


//
// Shading
//

float checker(vec3 p, vec3 dxdp, vec3 dydp) {
  vec3 q = sign(mod(p, 2.0) - 1.0);
  // Naive version
  // return 0.5 + 0.5 * q.x * q.y * q.z;

  // Approximate pixel coverage by box (reasonably over-estimate by abs)
  vec3 b = abs(dxdp) + abs(dydp);

  // Integrate 3d checker on the pixel coverage based on "separable" xor formula
  vec3 v0 = mod(p - b / 2.0, 2.0);
  vec3 v1 = mod(p + b / 2.0, 2.0);
  vec3 integrals = (abs(v1 - 1.0) - abs(v0 - 1.0)) / b;
  // return 0.5 + 0.5 * integrals.x * integrals.y * integrals.z;

  // Pick two dominant directions to integrate since
  // e.g. `b.y = 0` for horizontal plane and above formula gets zero division.
  float m = min(min(b.x, b.y), b.z);
  return 0.5 + 0.5 * (b.x == m ? q.x : integrals.x)
                   * (b.y == m ? q.y : integrals.y)
                   * (b.z == m ? q.z : integrals.z);
}

vec3 shadeSurface(
    vec3 p, vec3 normal, vec3 ray_orig, vec3 ray_dir,
    vec3 dxdp, vec3 dydp, SceneInfo info) {
  if (DEBUG_NORMAL) {
    return (0.5 + 0.5 * normal);
  }

  vec3 base_color = vec3(1.0);
  if (info.id == kIdGround) {
    base_color = OZN.yxx * mix(0.2, 1.2, checker(p, dxdp, dydp));
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

  float LdotN = max(0.0, dot(L, N));
  float HdotN = max(0.0, dot(H, N));

  vec3 color = vec3(0.0);

  // Phong's ambient
  color += PHONG_AMBIENT;

  // Lambertian diffuse
  color += base_color * LIGHT_COLOR * LdotN  * DIFFUSE_COEFF;

  // Phong's specular
  color += LIGHT_COLOR * pow(HdotN, PHONG_SPECULAR)   * SPECULAR_COEFF;

  return color;
}

vec3 shadeEnvironment(vec3 ray_dir) {
  float t = 0.5 + 0.5 * ray_dir.y; // \in [0, 1]
  t = smoothstep(0.0, 1.0, t);
  return mix(SKY_COLOR_RANGE[0], SKY_COLOR_RANGE[1], t);
}


//
// Main logic
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
    color = shadeEnvironment(ray_dir);
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
