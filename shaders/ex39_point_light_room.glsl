//
// Room with single point light
//

#include "common_v0.glsl"
const vec3 OZN = vec3(1.0, 0.0, -1.0);

float AA = 2.0;

// Ray intersection
float RAY_MAX_T = 100.0;

// Ray march
int   RM_MAX_ITER = 100;
float RM_SURFACE_DISTANCE = 0.0001;
float RM_NORMAL_DELTA = 0.001;

// Radiance source (degamma sRGB)
vec3 POINT_LIGHT_LOC = vec3(0.0, 1.8, 0.0);
vec3 POINT_LIGHT_RADIANCE = vec3(1.0) * M_PI; // at 1 meter away
vec3 ADHOC_ENV_COEFF = vec3(0.03);

// Tonemap (attains value 1 at Low + exp(A * (1 - Low) - 1)) / A)
float TONEMAP_A = 70.0;
float TONEMAP_L = 1.0;

// Camera
float CAMERA_YFOV = 39.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(0.0, 1.0, 5.0);
vec3  CAMERA_LOOKAT = vec3(0.0, 1.0, 0.0);
float CAMERA_SCALE_TIME = 0.0 / 32.0;


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

float Sdf_lineSegmentByEndpoints(vec3 p, vec3 v0, vec3 v1) {
  vec3 v = v1 - v0;
  vec3 n = normalize(v);
  return Sdf_lineSegment(p - v0, n, 0.0, length(v));
}

vec2 SdfOp_revolution(vec3 p) {
  return vec2(length(p.xz), p.y);
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

  //
  // Point light shield
  //
  {
    vec3 loc = POINT_LIGHT_LOC;
    float size = 0.2;
    float thickness = 0.01;
    vec2 q = SdfOp_revolution(p - loc);
    float sd = Sdf_lineSegmentByEndpoints(vec3(q.xy, 0), OZN.xyy * size, OZN.yxy * size);
    sd = abs(sd) - thickness;
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }

  //
  // Box room
  //
  {
    // y = 0
    vec3 loc = vec3(0, 0, 0);
    vec3 size = vec3(1.0, 0.01, 1.0);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // y = 2
    vec3 loc = vec3(0, 2, 0);
    vec3 size = vec3(1.0, 0.01, 1.0);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // x = +1
    vec3 loc = vec3(+1, 1, 0);
    vec3 size = vec3(0.01, 1.0, 1.0);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // x = -1
    vec3 loc = vec3(-1, 1, 0);
    vec3 size = vec3(0.01, 1.0, 1.0);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  {
    // z = -1
    vec3 loc = vec3(0, 1, -1);
    vec3 size = vec3(1.0, 1.0, 0.01);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }

  //
  // Box
  //
  {
    vec3 loc = vec3(0, 0.25, 0);
    vec3 size = vec3(0.5, 0.25, 0.5);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }

  //
  // Sphere
  //
  {
    vec3 loc = vec3(0.0, 0.75, 0.0);
    float r = 0.25;
    float sd = Sdf_sphere(p - loc, r);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  return ret;
}


//
// Shading
//

float getSoftRayOcculusion(vec3 orig, vec3 dir, float t_min, float t_max) {
  float ud_occ = 1e30;
  float sd_last = 0.0;
  for (float t = t_min; t < t_max; ) {
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
  float SOFT_OCC_WIDTH = 0.05;
  return smoothstep(0.0, 1.0, ud_occ / SOFT_OCC_WIDTH);
}

vec3 Brdf_f(
    vec3 n, vec3 wo, vec3 wi,
    vec3 diffuse_albedo, float beckmann_stddev) {

  vec3 h = normalize(wo + wi); // this becomes m for microfacet specular
  float dot_no = max(0.0001, dot(n, wo));
  float dot_ni = max(0.0001, dot(n, wi));
  float dot_nh = max(0.0001, dot(n, h));
  float dot_ho = max(0.0001, dot(h, wo));
  float dot_hi = max(0.0001, dot(h, wi));

  //
  // Microfacet specular BRDF (m: half vector)
  //   F(m, wi) D(n, m) G(n, m, wi, wo) / 4 (n.wo) (n.wi)
  //
  #define POW5(X) ((X) * (X) * (X) * (X) * (X))
  #define POW4(X) ((X) * (X) * (X) * (X))

  // Fresnel equation reflectance (IOR = 1.5) by Schlick's approx
  const float F1 = 0.04;
  float F = F1 + (1.0 - F1) * POW5(1.0 - dot_ho);

  // Beckmann surface's slope distribution stddev
  float stddev = beckmann_stddev;

  // Distribution of normal
  float ta = tan(acos(dot_nh));
  float gaussian = exp(- (ta / stddev) * (ta / stddev) / 2) / (sqrt(2.0 * M_PI) * stddev);
  float D = gaussian / POW4(dot_nh);

  // Corresponding "height correlated" masking-shadowing function by [3/3] Pade approx.
  #define G_PADE33(X) \
      (0.0 + 42.5770668488687*X + -2.73558953267639e-13*X*X + 3.54808890407244*X*X*X) / \
      (16.9857921414919 + 21.2885334244342*X + 9.90837874920349*X*X + 1.77404445203615*X*X*X)
  #define G_APPROX(X) min(1.0, G_PADE33((X)))
  float mu_wo = 1.0 / tan(acos(dot_no));
  float mu_wi = 1.0 / tan(acos(dot_ni));
  float G_wo = G_APPROX(mu_wo / stddev);
  float G_wi = G_APPROX(mu_wi / stddev);
  float G2 = (G_wo * G_wi) / (G_wo + G_wi - G_wo * G_wi);

  float brdf_microfacet_spec =
      (F * D * G2 * step(0.0, dot_ho) * step(0.0, dot_hi)) / (4.0 * dot_no * dot_ni);

  //
  // Lambertian diffuse BRDF
  //
  vec3 brdf_diffuse = diffuse_albedo / M_PI;

  // Mix by microfacet fresnel reflectance
  vec3 brdf_total = (1.0 - F) * brdf_diffuse + vec3(brdf_microfacet_spec);

  // [debug]
  // return brdf_diffuse;
  // return vec3(brdf_microfacet_spec);

  return brdf_total;
}

vec3 shadeSurface(
    vec3 p, vec3 normal, vec3 ray_orig, vec3 ray_dir,
    vec3 dxdp, vec3 dydp, SceneInfo info) {
  // [debug] normal
  // return (0.5 + 0.5 * normal);
  // [debug] frontface red, backface green
  // return vec3(max(0, dot(normal, -ray_dir)), max(0, -dot(normal, -ray_dir)), 0);

  vec3 base_color = vec3(1.0);
  if (info.id >= kIdOtherMin) {
    float t = info.id - kIdOtherMin;
    base_color = Quick_color(Quick_hash(t, 123456.0));
  }
  // [debug]
  // return base_color;

  vec3 Lo = vec3(0);
  vec3 n = normal;
  vec3 wo = -ray_dir;
  {
    vec3 v = POINT_LIGHT_LOC - p;
    float l = length(v);
    vec3 wi = v / l;
    vec3 L = POINT_LIGHT_RADIANCE / (l * l);

    float light_occ = getSoftRayOcculusion(p, wi, 0.01, l);
    vec3 brdf = Brdf_f(n, wo, wi, base_color, 0.2);
    float dot_ni = max(0.0, dot(n, wi));
    Lo += brdf * L * light_occ * dot_ni;
  }
  Lo += base_color * ADHOC_ENV_COEFF;
  return Lo;
}

vec3 shadeEnvironment(vec3 ray_orig, vec3 ray_dir) {
  return vec3(0);
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

vec3 singleSample(vec2 frag_coord, vec3 ray_orig, mat3 ray_xform) {
  // Setup camera ray
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
  return pivotTransform_v2(CAMERA_LOC, CAMERA_LOOKAT, 2.0 * M_PI * delta);
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

  // Tonemap
  {
    float l = TONEMAP_L;
    float a = TONEMAP_A;
    vec3 x = color;
    color = min(x, vec3(l)) + log(a * (max(x, vec3(l)) - l) + 1.0) / a;
  }
  color = pow(color, vec3(1.0 / 2.2));
  frag_color = vec4(color, 1.0);
}
