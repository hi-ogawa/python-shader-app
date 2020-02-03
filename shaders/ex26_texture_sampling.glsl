//
// Procedual texture sampling
// - cf.
//   - OpenGL spec 8.14.1 Scale Factor ...
//     - definition of rho (scale factor) based on
//       derivative of (u(x, y), v(x, y)) where (x, y) : window coord.
//   - http://iquilezles.org/www/articles/checkerfiltering/checkerfiltering.htm
//   - http://www.iquilezles.org/www/articles/filtering/filtering.htm
//

#include "common_v0.glsl"
#define OZ vec2(1.0, 0.0)

float AA = 1.0;
float SCALE_TIME = 1.0 / 48.0;
float RAY_MAX_T = 1000.0;

bool USE_ADAPTIVE = true;
bool USE_CHECKER1D_INTEGRATED = true;
bool USE_CHECKER2D_INTEGRATED = false;

float BASE_ADAPTIVE_ITER = 3.0;
float MAX_ADAPTIVE_ITER = 6.0;
float DEBUG_FAC = 0.8;
bool  DEBUG_FAC_ANIMATE = false;
float DEBUG_FAC_ANIMATE_SCALE_TIME = 1.0 / 8.0;

float CAMERA_YFOV = 30.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(1.0, 0.5, 2.0) * 8.0;
vec3  CAMERA_LOOKAT = vec3(0.0, 0.0, 0.0);

vec3  SKY_COLOR_RANGE[2] = vec3[2](vec3(0.3), vec3(0.85, 0.9, 0.9));

// Misc container
struct SceneInfo {
  float t;  // signed distance, 1d ray coordinate, etc..
  float id; // id associated with state t
};

float kIdChecker = 0.0;


float sampleChecker1d(vec2 p, vec2 dxdp, vec2 dydp) {
  // Naive version
  // return floor(mod(p.x, 2.0));

  // Approximate pixel coverage
  float d = (abs(dxdp) + abs(dydp)).x; // only along 1d x
  float x = p.x;

  {
    // Integrate 1d checker on [x - d / 2, x + d / 2]
    float x0 = mod(p.x - d / 2.0, 2.0);
    float x1 = x0 + d;
    float x1mod = mod(x1, 2.0);
    float integral =
        floor(x1 / 2.0) + max(x1mod - 1.0, 0.0) - max(x0 - 1.0, 0.0);
    // return integral / d;
  }

  {
    // Integrate 1d checker on [x0, x1] based on "xor formula"
    float x0 = mod(p.x - d / 2.0, 2.0);
    float x1 = mod(x0 + d, 2.0);
    float integral = abs(x1 - 1.0) - abs(x0 - 1.0);
    return 0.5 + 0.5 * integral / d;
  }
}

float sampleChecker2d(vec2 p, vec2 dxdp, vec2 dydp) {
  {
    // Naive version
    vec2 q = sign(mod(p, 2.0) - 1.0);
    // return 0.5 - 0.5 * q.x * q.y;
  }

  // Approximate pixel coverage
  vec2 l = abs(dxdp) + abs(dydp); // reasonably over-estimate by abs

  // Integrate 2d checker on the pixel coverage based on "separable" xor formula
  vec2 v0 = mod(p - l / 2.0, 2.0);
  vec2 v1 = mod(p + l / 2.0, 2.0);
  vec2 integrals = abs(v1 - 1.0) - abs(v0 - 1.0);
  return 0.5 - 0.5 * (integrals.x * integrals.y) / (l.x * l.y);
}

float sampleChecker(vec2 p) {
  vec2 q = sign(mod(p, 2.0) - 1.0);
  return 0.5 - 0.5 * q.x * q.y;
}

vec3 sampleCheckerAdaptive(
    vec3 p, vec3 dxdp, vec3 dydp) {
  vec2 q = p.xz;
  vec2 v1 = abs(dxdp.xz);
  vec2 v2 = abs(dydp.xz);
  mat2 T = mat2(v1, v2);

  float n1 = floor(length(v1));
  float n2 = floor(length(v2));
  n1 = min(n1 + BASE_ADAPTIVE_ITER, MAX_ADAPTIVE_ITER);
  n2 = min(n2 + BASE_ADAPTIVE_ITER, MAX_ADAPTIVE_ITER);

  float fac = 0.0;
  for (float i = 0.0; i < n1; i++) {
    for (float j = 0.0; j < n2; j++) {
      // Pick up center of n1 x n2 sub-pixel cells
      vec2 q_fract = -0.5 + (0.5 + vec2(i, j)) / vec2(n1, n2);
      fac += sampleChecker(q + T * q_fract);
    }
  }
  fac /= (n1 * n2);
  vec3 color = vec3(fac);

  // [Debug] visualize adaptive size
  // - as it can be seen from `debug_color = vec3(n1, 0.0, 0.0)`,
  //   dxdp is not a problem for horizontal surface.
  if (DEBUG_FAC_ANIMATE) {
    float t = DEBUG_FAC_ANIMATE_SCALE_TIME * iTime;
    DEBUG_FAC = mix(0.2, 0.9, 1.0 - abs(mod(t, 2.0) - 1.0));
  }
  vec3 debug_color;
  // debug_color = abs(dxdp.x) * OZ.xxx;
  // debug_color = abs(dxdp.z) * OZ.xxx;
  // debug_color = vec3(n1, 0.0, 0.0) / MAX_ADAPTIVE_ITER;
  debug_color = vec3(0.0, n2, 0.0) / MAX_ADAPTIVE_ITER;
  color = mix(color, debug_color, DEBUG_FAC);
  return color;
}

SceneInfo rayIntersect(vec3 orig, vec3 dir) {
  SceneInfo result;
  result.t = RAY_MAX_T;

  // Check double-faced ground
  if (orig.y * dir.y < 0) {
    float theta = atan(length(dir.xz), abs(dir.y));
    result.t = abs(orig.y) / cos(theta);
    result.id = kIdChecker;
  }

  return result;
}

vec3 shadeSurface(vec3 p, vec3 dxdp, vec3 dydp) {
  vec3 color;
  if (USE_ADAPTIVE) {
    color = sampleCheckerAdaptive(p, dxdp, dydp);
  } else
  if (USE_CHECKER1D_INTEGRATED) {
    float fac = sampleChecker1d(p.xz, dxdp.xz, dydp.xz);
    color = vec3(fac);
  } else
  if (USE_CHECKER2D_INTEGRATED) {
    float fac = sampleChecker2d(p.xz, dxdp.xz, dydp.xz);
    color = vec3(fac);
  }
  return color;
}

vec3 shadeEnvironment(vec3 ray_dir) {
  float t = 0.5 + 0.5 * ray_dir.y; // \in [0, 1]
  t = smoothstep(0.0, 1.0, t);
  return mix(SKY_COLOR_RANGE[0], SKY_COLOR_RANGE[1], t);
}

float intersect_Line_Plane(vec3 p, vec3 v, vec3 q, vec3 n) {
  // <p + t v - q, n> = 0
  // assert: not v // n
  return dot(q - p, n) / dot(v, n);
}

vec3 singleSample(vec2 frag_coord, mat3 inv_view_xform, mat4 camera_xform) {
  // Setup camera ray
  vec3 ray_orig = vec3(camera_xform[3]);
  mat3 ray_xform = mat3(camera_xform) * mat3(OZ.xyy, OZ.yxy, -OZ.yyx) * inv_view_xform;
  vec3 ray_dir = normalize(ray_xform * vec3(frag_coord, 1.0));

  // Ray test
  vec3 color = vec3(0.0);
  SceneInfo info = rayIntersect(ray_orig, ray_dir);
  if (info.t < RAY_MAX_T) {
    vec3 p = ray_orig + info.t * ray_dir;

    if (info.id == kIdChecker) {
      // Shade checker pattern with adaptive sampling
      // based on ground coverage of window pixel
      vec3 ray_dir_x = ray_xform * vec3(frag_coord + OZ.xy, 1.0);
      vec3 ray_dir_y = ray_xform * vec3(frag_coord + OZ.yx, 1.0);
      vec3 normal = OZ.yxy;
      float tx = intersect_Line_Plane(ray_orig, ray_dir_x, p, normal);
      float ty = intersect_Line_Plane(ray_orig, ray_dir_y, p, normal);
      vec3 dxdp = ray_orig + tx * ray_dir_x - p;
      vec3 dydp = ray_orig + ty * ray_dir_y - p;
      color = shadeSurface(p, dxdp, dydp);
    }
  } else {
    color = shadeEnvironment(ray_dir);
  }
  return color;
}

mat4 getCameraTransform(vec4 mouse, vec2 resolution) {
  bool mouse_activated, mouse_down;
  vec2 last_click_pos, last_down_pos;
  getMouseState(mouse, mouse_activated, mouse_down, last_click_pos, last_down_pos);

  vec2 delta = OZ.yy;
  delta.x += SCALE_TIME * 2.0 * M_PI * iTime;
  if (mouse_activated && mouse_down) {
    delta += 2.0 * M_PI * (last_down_pos - last_click_pos) / resolution;
  }
  return pivotTransform(CAMERA_LOC, CAMERA_LOOKAT, delta);
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
  frag_color = vec4(color, 1.0);
}
