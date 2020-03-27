//
// Homogenous volume light transport Monte-Carlo
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: size
      size: 1024

samplers:
  - name: buf
    type: framebuffer
    size: $default
    mipmap: false
    wrap: clamp
    filter: nearest
    internal_format: GL_RGBA32F

programs:
  - name: mainImage1
    samplers: [buf]
    output: buf

  - name: mainImage
    samplers: [buf]
    output: $default

offscreen_option:
  fps: 60
  num_frames: 256
%%config-end%%
*/

//
// SSBO definition
//

// Global state for interactive view
layout (std140, binding = 0) buffer Ssbo0 {
  int Ssbo_frame_count;
  bool Ssbo_mouse_down;
  vec2 Ssbo_mouse_down_p;
  vec2 Ssbo_mouse_click_p;
  mat4 Ssbo_camera_xform;
  vec3 Ssbo_lookat_p;
};


//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/ui_v0.glsl"
#include "utils/hash_v0.glsl"
#include "utils/sampling_v0.glsl"


//
// Scene parameters
//

// homogeneous volume
const float kSigmaAbs = 0.0;
const float kSigmaSca = 0.1;
const float kSigmaAtt = kSigmaAbs + kSigmaSca;

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(-2.0, 0.5, 4.0);
const vec3  kLookatP = vec3(0.0);

// scene geometry
const int kSceneType = 1;

// 2nd ray surface offset
const float kSurfaceTmin = 1e-4;

// For Volume_Li, and Diffuse_Li (direct lighting if length = 0)
const int kMaxVolumePathLength = 2;
const int kMaxDiffusePathLength = 2;

// NOTE: Clamp high radiance bounce from boxes covering point light.
const float kAdhocDiffuseIndirectClamp = 0.5;


struct Ray {
  vec3 o; // origin
  vec3 d; // direction
  float tmax;
};

struct Intersection {
  vec3 p; // point
  vec3 n; // normal
};

struct Sphere {
  vec3 c;  // center
  float r; // radius
};

struct Box {
  vec3 c; // center
  vec3 s; // size as vector from center to corner (assert > 0)
};

struct PointLight {
  vec3 p;   // position
  vec3 rad; // radiance at 1m away from p
};


bool Sphere_intersect(
    Sphere self, Ray ray, out Intersection isect, out float hit_t) {
  vec3 v = self.c - ray.o;
  float l = length(v);
  if (l <= self.r) { return false; }

  float dot_vd = dot(v, ray.d);
  if (dot_vd <= 0) { return false; }

  vec3 q = ray.o + dot(v, ray.d) * ray.d;
  float s = sqrt(dot2(self.r) - dot2(self.c - q));
  hit_t = dot_vd - s;
  if (ray.tmax <= hit_t) { return false; }

  isect.p = ray.o + hit_t * ray.d;
  isect.n = normalize(isect.p - self.c);
  return true;
}

bool Box_intersect(
    Box self, Ray ray, out Intersection isect, out float hit_t) {

  // Interesect to six planes
  vec3 bb_min = self.c - self.s;
  vec3 bb_max = self.c + self.s;
  vec3 t0 = (bb_min - ray.o) / ray.d;  // "negative" planes
  vec3 t1 = (bb_max - ray.o) / ray.d;  // "positive" planes

  // Determine ray going in/out of parallel planes
  float t_in  = reduceMax(min(t0, t1));
  float t_out = reduceMin(max(t0, t1));

  bool hit = 0.0 < t_in && t_in < t_out && t_in < ray.tmax;
  if (!hit) { return false; }

  // hit distance
  hit_t = t_in;

  // position/normal
  vec3 p = ray.o + hit_t * ray.d;
  vec3 v = (p - self.c) / self.s;
  int i = reduceArgmax(abs(v));
  vec3 n = vec3(0.0);
  n[i] = sign(v[i]);
  isect.p = p;
  isect.n = n;
  return true;
}

// NOTE: ray.tmax is used to represent hit distance
bool Scene_intersect(inout Ray ray, bool any_hit, out Intersection isect) {
  bool hit_main = false;

  #define PRIMITIVE(TYPE, OBJ)                                            \
    {                                                                     \
      float hit_t;                                                        \
      Intersection prim_isect;                                            \
      bool hit = TYPE##_intersect(OBJ, ray, /*out*/ prim_isect, hit_t);   \
      if (hit) {                                                          \
        hit_main = true;                                                  \
        ray.tmax = hit_t;                                                 \
        isect.p = prim_isect.p;                                           \
        isect.n = prim_isect.n;                                           \
        if (any_hit) { return true; }                                     \
      }                                                                   \
    }                                                                     \

  if (kSceneType == 0) {
    {
      Box prim; prim.c = vec3(0.0, -1.0, 0.0); prim.s = vec3(8.0, 0.05, 8.0);
      PRIMITIVE(Box, prim);
    }

    {
      Box prim; prim.c = vec3(1.0, 0.0, 0.0); prim.s = vec3(0.5);
      PRIMITIVE(Box, prim);
    }

    {
      Sphere prim; prim.c = vec3(-1.0, 0.0, 0.0); prim.r = 0.5;
      PRIMITIVE(Sphere, prim);
    }

    {
      Sphere prim; prim.c = vec3(0.0, 0.0, -1.0); prim.r = 0.5;
      PRIMITIVE(Sphere, prim);
    }
  }

  if (kSceneType == 1) {
    {
      // Ground
      Box prim; prim.c = vec3(0.0, -1.0, 0.0); prim.s = vec3(4.0, 0.05, 4.0);
      PRIMITIVE(Box, prim);
    }

    {
      // Sphere under spot light
      Sphere prim; prim.c = vec3(0.0, 0.2, 0.0); prim.r = 0.5;
      PRIMITIVE(Sphere, prim);
    }

    // Boxes covering point light
    float h = 2.0;
    float d = 0.018;
    float dd = 0.02;
    {
      Box prim; prim.c = vec3(+d, h, 0.0); prim.s = vec3(0.01, d, dd);
      PRIMITIVE(Box, prim);
    }
    {
      Box prim; prim.c = vec3(-d, h, 0.0); prim.s = vec3(0.01, d, dd);
      PRIMITIVE(Box, prim);
    }
    {
      Box prim; prim.c = vec3(0.0, h, +d); prim.s = vec3(dd, d, 0.01);
      PRIMITIVE(Box, prim);
    }
    {
      Box prim; prim.c = vec3(0.0, h, -d); prim.s = vec3(dd, d, 0.01);
      PRIMITIVE(Box, prim);
    }
    {
      Box prim; prim.c = vec3(0.0, h + d, 0.0); prim.s = vec3(dd, 0.001, dd);
      PRIMITIVE(Box, prim);
    }
  }

  return hit_main;
};

// forward decl.
float Scene_evaluateTransmission(Ray ray);

void evaluatePointLight(PointLight light, Intersection isect, out vec3 wi, out vec3 Le) {
  vec3 v = light.p - isect.p;
  float l = length(v);
  wi = v / l;

  Ray ray;
    ray.d = wi;
    ray.o = isect.p + kSurfaceTmin * ray.d;
    ray.tmax = l;
  Intersection isect_2nd;

  Le = vec3(0.0);

  // NOTE: here dot(isect.n, wi) > 0 is not checked
  if (!Scene_intersect(ray, /*any_hit*/ true, isect_2nd)) {
    Le = light.rad / (l * l);
    Le *= Scene_evaluateTransmission(ray);
  }
}

void Scene_evaluateLight(Intersection isect, out vec3 wi, out vec3 Le) {
  PointLight light;
  light.p   = vec3(0.0, 2.0, 0.0);
  light.rad = vec3(1.0) * M_PI * 4.0;
  evaluatePointLight(light, isect, wi, Le);
}

void Scene_evaluateBrdf(Intersection isect, vec3 wi, out vec3 brdf) {
  brdf = vec3(1.0) / M_PI;
}

void Scene_sampleBrdfCosine(Intersection isect, out vec3 wi, out vec3 brdf, out float pdf) {
  brdf = vec3(1.0) / M_PI;
  vec2 u = hash42(vec4(isect.p, iFrame));

  vec3 p;
  Sampling_hemisphereCosine(u, /*out*/ p, pdf);
  wi = T_zframe(isect.n) * p;
}


// Return throughput-update irregardless of volume scattering event
float Scene_sampleVolume(Ray ray, out Intersection isect, out bool hit_vol) {
  // Monte carlo evaluation of
  //   (\int_{t < tmax} exp(- s t) s_sca L_phase) + exp(-s tmax) L_surf
  float u = hash41(vec4(ray.d, hash41(vec4(ray.o, iFrame))));

  // Sample from density "s exp(- s t)" clamped at t = tmax
  float t = - log(1.0 - u) / kSigmaAtt;

  // clamped delta part (right term)
  if (ray.tmax <= t) {
    hit_vol = false;
    return 1.0;
  }

  // continuous density part (left term)
  isect.p = ray.o + t * ray.d;
  hit_vol = true;
  return kSigmaSca / kSigmaAtt;
}

float Scene_evaluateTransmission(Ray ray) {
  float t = ray.tmax;
  return exp(- kSigmaAtt * t);
}

void Scene_evaluatePhaseFunction(Intersection isect, vec3 wi, out vec3 phase) {
  // uniform phase function
  phase = vec3(1.0) / (4.0 * M_PI);
}

void Scene_samplePhaseFunction(Intersection isect, out vec3 wi, out vec3 phase, out float pdf) {
  // uniform phase function
  phase = vec3(1.0) / (4.0 * M_PI);
  vec2 u = hash42(vec4(isect.p, iFrame));
  Sampling_sphereUniform(u, wi, pdf);
}


//
// Integrators
//

vec3 Volume_Li(Ray ray) {
  vec3 L = vec3(0.0);
  vec3 throughput = vec3(1.0);

  for (int i = 0; i <= kMaxVolumePathLength; i++) {
    Intersection isect;
    bool hit_scene = Scene_intersect(/*inout*/ ray, /*any_hit*/ false, /*out*/ isect);

    Intersection isect_vol;
    bool hit_vol;
    throughput *= Scene_sampleVolume(ray, /*out*/ isect_vol, hit_vol);

    if (hit_vol) {
      //
      // Monte carlo sample of radiance contribution from path with length i
      //
      {
        // Sample light
        vec3 wi;
        vec3 Le;
        Scene_evaluateLight(isect_vol, /*out*/ wi, Le);

        // Evaluate phase function
        vec3 phase;
        Scene_evaluatePhaseFunction(isect_vol, wi, /*out*/ phase);
        L += throughput * phase * Le;
      }

      //
      // Sample next path direction and accumulate throughput
      //
      {
        // Sample phase function
        vec3 phase;
        vec3 wi;
        float pdf;
        Scene_samplePhaseFunction(isect_vol, /*out*/ wi, phase, pdf);

        // Accumulate throughput
        throughput *= phase / pdf;
        ray.o = isect_vol.p;
        ray.d = wi;
        ray.tmax = 1e30;
      }
      continue;
    }


    //
    // FROM HERE, EXACTLY SAME AS `Diffuse_Li`
    //

    if (!hit_scene) {
      break;
    }

    //
    // Monte carlo sample of radiance contribution from path with length i
    //
    {
      // Sample light
      vec3 wi;
      vec3 Le;
      Scene_evaluateLight(isect, /*out*/ wi, Le);

      if (i > 0) {
        Le = min(Le, vec3(kAdhocDiffuseIndirectClamp));
      }

      // Evalute BRDF
      vec3 brdf;
      Scene_evaluateBrdf(isect, wi, /*out*/ brdf);
      L += throughput * brdf * Le * clamp0(dot(isect.n, wi));
    }

    //
    // Sample next path direction and accumulate throughput
    //
    {
      // Sample BRDF (this time for throughput)
      vec3 brdf;
      vec3 wi;
      float pdf; // importance pdf(wi) for brdf(wo, wi) * dot(n, wi)
      Scene_sampleBrdfCosine(isect, /*out*/ wi, brdf, pdf);

      // Accumulate throughput
      throughput *= brdf * dot(isect.n, wi) / pdf;
      ray.o = isect.p + kSurfaceTmin * wi;
      ray.d = wi;
      ray.tmax = 1e30;
    }
  }
  return L;
}

vec3 Diffuse_Li(Ray ray) {
  vec3 L = vec3(0.0);
  vec3 throughput = vec3(1.0);

  for (int i = 0; i <= kMaxDiffusePathLength; i++) {
    Intersection isect;
    if (!Scene_intersect(/*inout*/ ray, /*any_hit*/ false, /*out*/ isect)) {
      break;
    }

    //
    // Monte carlo sample of radiance contribution from path with length i
    //
    {
      // Sample light
      vec3 wi;
      vec3 Le;
      Scene_evaluateLight(isect, /*out*/ wi, Le);

      // Sample BRDF
      vec3 brdf;
      Scene_evaluateBrdf(isect, wi, /*out*/ brdf);
      L += throughput * brdf * Le * clamp0(dot(isect.n, wi));
    }

    //
    // Sample next path direction and accumulate throughput
    //
    {
      // Sample BRDF (this time for throughput)
      vec3 brdf;
      vec3 wi;
      float pdf; // importance pdf(wi) for brdf(wo, wi) * dot(n, wi)
      Scene_sampleBrdfCosine(isect, /*out*/ wi, brdf, pdf);

      // Accumulate throughput
      throughput *= brdf * dot(isect.n, wi) / pdf;
      ray.o = isect.p + kSurfaceTmin * wi;
      ray.d = wi;
      ray.tmax = 1e30;
    }
  }
  return L;
}


vec3 Position_Li(Ray ray) {
  vec3 L = vec3(0.0);

  Intersection isect;
  bool hit = Scene_intersect(ray, /*any_hit*/ false, /*out*/ isect);
  if (hit) {
    // Shade based on hit position relative to M/m
    vec3 M = vec3(+10.0);
    vec3 m = vec3(-10.0);
    L = (isect.p - m) / (M - m);
  }
  return L;
}

vec3 Normal_Li(Ray ray) {
  vec3 L = vec3(0.0);

  Intersection isect;
  bool hit = Scene_intersect(ray, /*any_hit*/ false, /*out*/ isect);
  if (hit) {
    L = 0.5 + 0.5 * isect.n;
  }
  return L;
}


//
// Camera setup routines
//

void generateRay(
    vec2 frag_coord, vec2 resolution, float yfov, mat4 camera_xform, out Ray ray) {
  mat3 inv_view_xform = T_invView(yfov, resolution);
  vec3 ray_orig = vec3(camera_xform[3]);
  mat3 ray_xform = mat3(camera_xform) * T_scale3(vec3(1.0, 1.0, -1.0)) * inv_view_xform;

  ray.o = vec3(camera_xform[3]);
  ray.d = normalize(ray_xform * vec3(frag_coord, 1.0));
  ray.tmax = 1e30;
}


//
// Rendering
//

vec3 renderPixel(vec2 frag_coord) {
  // Uniform random offset
  vec2 u = hash32(vec3(frag_coord, iFrame));
  vec2 sub_frag_coord = frag_coord - 0.5 + u;

  // Setup camera and generate ray
  Ray ray;
  generateRay(sub_frag_coord, iResolution.xy, kYfov, Ssbo_camera_xform, /*out*/ ray);

  // Run integrator
  vec3 L;
  // L = Normal_Li(ray);
  // L = Position_Li(ray);
  // L = Diffuse_Li(ray);
  L = Volume_Li(ray);
  return L;
}


void mainImage1(out vec4 frag_color, vec2 frag_coord, sampler2D buf){
  vec3 color_now = renderPixel(frag_coord);
  vec3 color_prev = texelFetch(buf, ivec2(frag_coord), 0).xyz;

  vec3 color = mix(color_prev, color_now, 1.0 / float(Ssbo_frame_count));
  if (Ssbo_frame_count == 1) {
    color = color_now;
  }
  frag_color.xyz = color;
}


//
// Display + Interactive state management
//

void mainImage(out vec4 frag_color, vec2 frag_coord, sampler2D buf){
  vec3 color = texelFetch(buf, ivec2(frag_coord), 0).xyz;
  color = pow(color, vec3(1.0 / 2.2)); // sRGB gamma
  frag_color = vec4(color, 1.0);

  // Manage global state by bottom-left fragment
  if (all(equal(frag_coord, vec2(0.5)))) {

    bool interacted = UI_handleCameraInteraction(
        iResolution.xy, iMouse, iKeyModifiers,
        kCameraP, kLookatP,
        Ssbo_mouse_down, Ssbo_mouse_down_p, Ssbo_mouse_click_p,
        Ssbo_camera_xform, Ssbo_lookat_p);

    Ssbo_frame_count += 1;

    if (interacted || (iFrame == 0)) {
      Ssbo_frame_count = 1;
    }
  }
}
