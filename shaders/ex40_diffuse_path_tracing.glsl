//
// Path tracing
//

/*
%%config-start%%
samplers:
  - name: fb
    type: framebuffer
    size: $default
    mipmap: false
    wrap: clamp
    filter: nearest

programs:
  - name: mainImage2
    output: fb
    samplers:
      - fb

  - name: mainImage1
    output: $default
    samplers:
      - fb

offscreen_option:
  fps: 60
  num_frames: 34
%%config-end%%
*/


#include "common_v0.glsl"
const vec3 OZN = vec3(1.0, 0.0, -1.0);

float AA = 1.0;

// Ray intersection
float RAY_MIN_T = 0.005;
float RAY_MAX_T = 100.0;

// Ray march
int   RM_MAX_ITER = 100;
float RM_SURFACE_DISTANCE = 0.0001;
float RM_NORMAL_DELTA = 0.001;

// Radiance source (degamma sRGB)
vec3 POINT_LIGHT_LOC = vec3(0.0, 1.8, 0.0);
vec3 POINT_LIGHT_RADIANCE = vec3(1.0) * M_PI * 0.5; // radiance at 1 meter away
vec3 ADHOC_ENV_COEFF = vec3(0.03);

// Tonemap (attains value 1 at Low + exp(A * (1 - Low) - 1)) / A)
float TONEMAP_A = 30.0;
float TONEMAP_L = 0.9;

// Camera
float CAMERA_YFOV = 39.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(0.0, 1.0, 5.0);
vec3  CAMERA_LOOKAT = vec3(0.0, 1.0, 0.0);
float CAMERA_SCALE_TIME = 0.0 / 32.0;

//
// Hash routines
//

float hash11(float t) {
  return fract(sin(t * 56789) * 56789);
}

float hash21(vec2 uv) {
  return hash11(hash11(uv[0]) + 2.0 * hash11(uv[1]));
}

float hash31(vec3 v) {
  return hash11(hash11(v[0]) + 2.0 * hash11(v[1]) + 3.0 * hash11(v[2]));
}

float hash41(vec4 v) {
  return hash11(hash11(v[0]) + 2.0 * hash11(v[1]) + 3.0 * hash11(v[2]) + 4.0 * hash11(v[3]));
}

vec2 hash32(vec3 v) {
  return vec2(hash31(v), hash41(vec4(v, 1.0)));
}

vec2 hash42(vec4 v) {
  return hash32(vec3(hash41(v.xyzw), hash41(vec4(v.yzwx)), hash41(vec4(v.zwxy))));
}


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
  vec3 diffuse_albedo;
};

float kIdOtherMin = 10.0;

SceneInfo mergeSceneInfo(SceneInfo info, float t, float id, vec3 diffuse_albedo) {
  if (info.t < t) {
    return info;
  }
  info.t  = t;
  info.id = id;
  info.diffuse_albedo = diffuse_albedo;
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
    float size = 0.15;
    float thickness = 0.02;
    vec2 q = SdfOp_revolution(p - loc);
    float sd = Sdf_lineSegmentByEndpoints(vec3(q.xy, 0), OZN.xyy * size, OZN.yxy * size);
    sd = abs(sd) - thickness;
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__), vec3(1.0));
  }

  //
  // Box room
  //
  {
    // y = 0
    vec3 loc = vec3(0, 0, 0);
    vec3 size = vec3(1.0, 0.01, 1.0);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__), OZN.xxx);
  }
  {
    // y = 2
    vec3 loc = vec3(0, 2, 0);
    vec3 size = vec3(1.0, 0.01, 1.0);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__), vec3(1.0));
  }
  {
    // x = +1
    vec3 loc = vec3(+1, 1, 0);
    vec3 size = vec3(0.01, 1.0, 1.0);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__), OZN.xyy);
  }
  {
    // x = -1
    vec3 loc = vec3(-1, 1, 0);
    vec3 size = vec3(0.01, 1.0, 1.0);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__), OZN.yxy);
  }
  {
    // z = -1
    vec3 loc = vec3(0, 1, -1);
    vec3 size = vec3(1.0, 1.0, 0.01);
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__), vec3(1.0));
  }

  //
  // Box
  //
  {
    vec3 loc = vec3(0, 0.75 / 2.0, 0);
    vec3 size = vec3(0.15, 0.75 / 2.0, 0.15);
    mat3 rot = rotate3(OZN.yxy * M_PI / 4.0);
    float sd = Sdf_box(rot * (p - loc), size);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__), vec3(1.0));
  }

  //
  // Sphere
  //
  {
    vec3 loc = vec3(0.0, 1.0, 0.0);
    float r = 0.25;
    float sd = Sdf_sphere(p - loc, r);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__), vec3(1.0));
  }
  return ret;
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

SceneInfo rayMarch_v2(vec3 orig, vec3 dir, float t_min, float t_max) {
  SceneInfo result;
  result.t = t_max;

  float t = t_min;
  for (int i = 0; i < RM_MAX_ITER; i++) {
    SceneInfo step = getSceneSdf(orig + t * dir);
    t += step.t;
    if (step.t < 0.0 || t_max <= t) {
      break;
    }
    if (abs(step.t) < RM_SURFACE_DISTANCE) {
      result = step;
      result.t = t;
      break;
    }
  }
  return result;
}

SceneInfo rayMarch(vec3 orig, vec3 dir) {
  return rayMarch_v2(orig, dir, 0.0, RAY_MAX_T);
}

struct Intersection {
  bool valid;
  vec3 p;
  vec3 n;
  SceneInfo info;
};

// TODO: seems something wrong when Sdf(orig + t_min * dir) < 0
Intersection rayIntersect_v2(vec3 orig, vec3 dir, float t_min, float t_max) {
  Intersection isect;
  isect.valid = false;
  isect.info = rayMarch_v2(orig, dir, t_min, t_max);
  if (isect.info.t >= t_max) {
    return isect;
  }
  isect.valid = true;
  isect.p = orig + isect.info.t * dir;
  isect.n = getNormal(isect.p);
  return isect;
}

Intersection rayIntersect(vec3 orig, vec3 dir) {
  return rayIntersect_v2(orig, dir, RAY_MIN_T, RAY_MAX_T);
}

void evaluateLight(
    Intersection isect, out vec3 wi, out vec3 Le, out float visibility) {
  vec3 v = POINT_LIGHT_LOC - isect.p;
  float l = length(v);
  wi = v / l;
  Le = POINT_LIGHT_RADIANCE / (l * l);
  visibility = float(!rayIntersect_v2(isect.p, wi, 0.01, l).valid);
  visibility *= step(0.0, dot(isect.n, wi)); // TODO: rayIntersect_v2 seems wrong
}

void evaluateBrdf(Intersection isect, vec3 wi, out vec3 brdf) {
  brdf = isect.info.diffuse_albedo / M_PI;
}

void Sampling_hemisphereCosine(vec2 u, out vec3 p, out float pdf) {
  float phi   = 2.0 * M_PI * u.x;
  float theta = 0.5 * acos(1.0 - 2.0 * u.y);
  p = inverseSphericalCoordinate(vec3(1.0, theta, phi));
  pdf = cos(theta) / M_PI;
}

void sampleBrdfCosine(Intersection isect, out vec3 wi, out vec3 brdf, out float pdf) {
  brdf = isect.info.diffuse_albedo / M_PI;
  vec2 u = hash42(vec4(isect.p, iFrame));

  // [debug]
  // u = hash32(isect.p);
  vec3 p;
  Sampling_hemisphereCosine(u, /*out*/ p, pdf);
  wi = zframeTransform(isect.n) * p;

  // [debug] uniform hemisphere sampling
  // float phi = 2.0 * M_PI * u.x;
  // float theta = acos(1.0 - u.y);
  // p = inverseSphericalCoordinate(vec3(1.0, theta, phi));
  // pdf = 1.0 / (2.0 * M_PI);
  // wi = zframeTransform(isect.n) * p;
}

const int MAX_PATH_LENGTH = 1;
const float INDIRECT_CLAMP = 2.0;

vec3 Integrator_Li(vec3 ray_orig, vec3 ray_dir) {
  vec3 L = vec3(0.0);
  vec3 throughput = vec3(1.0);

  vec3 pp = ray_orig;
  vec3 ww = ray_dir;
  for (int i = 0; i <= MAX_PATH_LENGTH; i++) {
    Intersection isect = rayIntersect(pp, ww);
    if (!isect.valid) {
      break;
    }

    //
    // Monte carlo sample of radiance contribution from path with length i
    //
    {
      // Sample light (delta distribution because point light)
      vec3 wi;
      vec3 Le;
      float visibility;
      evaluateLight(isect, /*out*/ wi, Le, visibility);

      // Sample BRDF (uniform distribution because diffuse)
      vec3 brdf;
      evaluateBrdf(isect, wi, /*out*/ brdf);

      // Adhoc clamp indirect bounce
      if (i > 0) {
        Le = min(Le, INDIRECT_CLAMP);
      }

      L += throughput * brdf * Le * visibility * dot(isect.n, wi);

      // [debug]
      // if (i == 0) {
      //   return vec3(max(0.0, visibility), 0.0, 0.0);
      // }

      // [debug]
      // if (i == 1) {
      //   return 0.5 + 0.5 * isect.n;
      //   return 0.5 + 0.5 * isect.p;
      //   return Le * visibility;
      // }
    }

    //
    // sample next path direction and accumulate throughput
    //
    {
      // Sample BRDF (this time for throughput)
      vec3 brdf;
      vec3 wi;
      float pdf; // importance pdf(wi) for brdf(wo, wi) * dot(n, wi)
      sampleBrdfCosine(isect, /*out*/ wi, brdf, pdf);

      // Accumulate throughput
      throughput *= brdf * dot(isect.n, wi) / pdf;
      pp = isect.p;
      ww = wi;

      // [debug]
      // throughput = vec3(1.0);

      // [debug]
      // float x = dot(ww, isect.n);
      // x = pdf;
      // x = ww.x;
      // return vec3(max(0.0, x), max(0.0, -x), 0.0);

      // [debug]
      // return 0.5 + 0.5 * ww / pdf;
    }
  }
  return L;
}

vec3 samplePixel(vec2 frag_coord, vec3 ray_orig, mat3 ray_xform) {
  vec2 u = hash32(vec3(frag_coord, iFrame));
  // [debug]
  // u = vec2(0.5);
  vec2 sub_frag_coord = frag_coord - 0.5 + u;
  vec3 ray_dir = normalize(ray_xform * vec3(sub_frag_coord, 1.0));
  return Integrator_Li(ray_orig, ray_dir);
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

void mainImage1(out vec4 frag_color, vec2 frag_coord, sampler2D fb) {
  vec3 color = texelFetch(fb, ivec2(floor(frag_coord)), 0).xyz;

  // Log curve
  float l = TONEMAP_L;
  float a = TONEMAP_A;
  vec3 x = color;
  color = min(x, vec3(l)) + log(a * (max(x, vec3(l)) - l) + 1.0) / a;

  // sRGB gamma
  color = pow(color, vec3(1.0 / 2.2));

  frag_color = vec4(color, 1.0);
}


void mainImage2(out vec4 frag_color, vec2 frag_coord, sampler2D fb) {
  // Initialize fb as black
  if (iFrame == 0) {
    frag_color = vec4(0.0);
    return;
  }

  // TODO: Re-initialize if there's interaction
  {
    bool mouse_activated, mouse_down;
    vec2 last_click_pos, last_down_pos;
    getMouseState(iMouse, mouse_activated, mouse_down, last_click_pos, last_down_pos);
  }

  // Setup coordinate system
  mat3 inv_view_xform = inverseViewTransform(CAMERA_YFOV, iResolution.xy);
  mat4 camera_xform = getCameraTransform(iMouse, iResolution.xy);
  vec3 ray_orig = vec3(camera_xform[3]);
  mat3 ray_xform = mat3(camera_xform) * mat3(OZN.xyy, OZN.yxy, -OZN.yyx) * inv_view_xform;

  // Accumulate color by running average
  vec3 color_now = samplePixel(frag_coord, ray_orig, ray_xform);
  vec3 color_prev = texelFetch(fb, ivec2(floor(frag_coord)), 0).xyz;
  vec3 color = mix(color_prev, color_now, 1.0 / float(iFrame));

  // [debug]
  // color = color_now;
  // color = color_prev;
  // color = mix(color_prev, color_now, 1 - 1 / iFrame);

  frag_color = vec4(color, 1.0);
}
