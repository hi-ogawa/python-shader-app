//
// 3d text
//

#include "common_v0.glsl"
#include "utils/overlay_v0.glsl"
const vec3 OZN = vec3(1.0, 0.0, -1.0);

// mainImage_2d
float AA = 2.0;
const vec2 BBOX_Y = vec2(-0.5, 1.5);
const vec2 CENTER = vec2(0.0, (BBOX_Y[0] + BBOX_Y[1]) / 2.0);

float Sdf_lineSegment(vec2 p, vec2 v, float t0, float t1) {
  // assert |v| = 1
  return distance(p, clamp(dot(p, v), t0, t1) * v);
}

float Sdf_lineSegment_v2(vec2 p, vec2 v, float t0, float t1, float w) {
  vec2 q = vec2(
    dot(vec2(v.y, -v.x), p),
    dot(v, p) - (t0 + t1) / 2.0);
  vec2 b = vec2(w / 2.0, (t0 + t1) / 2.0);

  vec2 sd2 = abs(q) - b;
  float m = max(sd2.x, sd2.y);
  return m < 0.0 ? m : length(max(sd2, vec2(0.0)));
}

float Sdf_arc(vec2 p, float r, float t0, float t1) {
  // assert 0 <= t0 < t1 < pi
  float s = mod(atan(p.y, p.x), 2.0 * M_PI);
  float s0 = 2.0 * M_PI * t0;
  float s1 = 2.0 * M_PI * t1;
  if (s0 <= s && s <= s1) {
    return abs(length(p) - r);
  }
  vec2 q1 = r * vec2(cos(s0), sin(s0));
  vec2 q2 = r * vec2(cos(s1), sin(s1));
  return min(distance(p, q1), distance(p, q2));
}

// TODO
// float Sdf_arc_v2(vec2 p, float r, float t0, float t1, float width) {}

float SdfOp_isoline(float sd, float _step, float width) {
  float t = mod(sd, _step);
  float ud_isoline = min(t, _step - t);
  float sd_isoline = ud_isoline - width / 2.0;
  return sd_isoline;
}

#define SDF_FONT(NAME, RULE) \
  float SdfFont_##NAME(vec2 p) { \
    float ud = 1e30; \
    RULE \
    return ud; \
  }
#define SDF_FONT_LINE(Q1, Q2) \
  ud = min(ud, Sdf_lineSegment_v2(p - (vec2 Q1), normalize(vec2 Q2 - vec2 Q1), 0.0, length(vec2 Q2 - vec2 Q1), 0.1));
#define SDF_FONT_ARC(C, R, T1, T2) \
  ud = min(ud, Sdf_arc(p - vec2 C, R, T1, T2));
#define SDF_FONT_POINT(C) \
  ud = min(ud, distance(p, vec2 C));

#define Ym2 -2.0/4.0
#define Ym1 -1.0/4.0
#define Y0  +0.0/4.0
#define Y1  +1.0/4.0
#define Y2  +2.0/4.0
#define Y3  +3.0/4.0
#define Y4  +4.0/4.0

#define dX  +1.0/4.0
#define Xm2 -2.0/4.0
#define Xm1 -1.0/4.0
#define X0  +0.0/4.0
#define X1  +1.0/4.0
#define X2  +2.0/4.0

SDF_FONT(H,
  SDF_FONT_LINE((Xm1, Y4), (Xm1, Y0))
  SDF_FONT_LINE((Xm1, Y2), (X1, Y2))
  SDF_FONT_LINE((X1, Y4), (X1, Y0))
)

SDF_FONT(E,
  SDF_FONT_LINE((Xm1, Y4), (Xm1, Y0))
  SDF_FONT_LINE((Xm1, Y4), (X1, Y4))
  SDF_FONT_LINE((Xm1, Y2), (X1, Y2))
  SDF_FONT_LINE((Xm1, Y0), (X1, Y0))
)

SDF_FONT(L,
  SDF_FONT_LINE((Xm1, Y4), (Xm1, Y0))
  SDF_FONT_LINE((Xm1, Y0), (X1, Y0))
)

SDF_FONT(O,
  SDF_FONT_LINE((Xm1, Y3), (Xm1, Y1))
  SDF_FONT_ARC ((X0, Y1), dX, 0.5, 1.0)
  SDF_FONT_LINE((X1, Y1), (X1, Y3))
  SDF_FONT_ARC ((X0, Y3), dX, 0.0, 0.5)
)

#undef SDF_FONT
#undef SDF_FONT_LINE
#undef SDF_FONT_ARC

struct SceneInfo {
  float t;
  float id;
};

SceneInfo mergeSceneInfo(SceneInfo info, float t, float id) {
  info.id = info.t < t ? info.id : id;
  info.t  = info.t < t ? info.t  : t ;
  return info;
}

SceneInfo getSceneSdf_2d(vec2 p) {
  SceneInfo result;
  result.t = 1e30;
  result = mergeSceneInfo(result, SdfFont_H(p), float(__LINE__));
  return result;
}


float AA_MULTI_SAMPLE = 3.0;
bool DEBUG_OVERLAY = false;

// Ray intersection
float RAY_MAX_T = 1000.0;

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
vec3  CAMERA_LOC =    vec3(1.0, 0.5, 2.0) * 3.0;
vec3  CAMERA_LOOKAT = vec3(0.0, 0.0, 0.0);
vec3  CAMERA_UP =     vec3(0.0, 1.0, 0.0);
float CAMERA_SCALE_TIME = 1.0 / 32.0;

float Sdf_sphere(vec3 p, float r) {
  return length(p) - r;
}

float Sdf_box(vec3 p, vec3 q) {
  vec3 sd3 = abs(p) - q;
  float m = max(max(sd3.x, sd3.y), sd3.z);
  return m < 0.0 ? m : length(max(sd3, vec3(0.0)));
}

float SdfOp_extrude(float y, float sd_zx, float bound_y) {
  float sd_y = abs(y) - bound_y;
  float m = max(sd_zx, sd_y);
  return m < 0.0 ? m : length(max(vec2(sd_zx, sd_y), vec2(0.0)));
}

float SdfOp_deepen(float sd, float w) {
  return sd - w;
}

float kIdOtherMin = 10.0;

SceneInfo getSceneSdf(vec3 p) {
  SceneInfo ret;
  ret.t = RAY_MAX_T;
  {
    float depth = 0.3;
    float line_width = 0.0;

    p.y += 0.5;
    p.xy = rotate2(- 0.5 * M_PI) * p.xy;
    float sd_H; {
      vec3 q = p;
      sd_H = SdfOp_extrude(q.y, SdfFont_H(q.zx) - line_width, depth);
    }
    float sd_E; {
      vec3 q = p;
      q.yz = rotate2(- 0.5 * M_PI) * q.yz;
      sd_E = SdfOp_extrude(q.y, SdfFont_E(q.zx) - line_width, depth);
    }
    float sd = max(sd_H, sd_E);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  return ret;
}

//
// Shading
//

vec3 shadeSurface(vec3 p, vec3 normal, vec3 ray_orig, vec3 ray_dir, SceneInfo info) {
  vec3 base_color = vec3(1.0);
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
    color = shadeSurface(p, normal, ray_orig, ray_dir, info);
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

void mainImage_3d(out vec4 frag_color, vec2 frag_coord) {
  // Setup coordinate system
  mat3 inv_view_xform = inverseViewTransform(CAMERA_YFOV, iResolution.xy);
  mat4 camera_xform = getCameraTransform(iMouse, iResolution.xy);

  // Averaging multisamples
  vec3 color = vec3(0.0);
  vec2 int_coord = floor(frag_coord);
  for (float i = 0.0; i < AA_MULTI_SAMPLE; i++) {
    for (float j = 0.0; j < AA_MULTI_SAMPLE; j++) {
      vec2 fract_coord = (0.5 + vec2(i, j) / 2.0) / AA_MULTI_SAMPLE;
      vec2 ms_frag_coord = int_coord + fract_coord;
      color += singleSample(ms_frag_coord, inv_view_xform, camera_xform);
    }
  }
  color /= (AA_MULTI_SAMPLE * AA_MULTI_SAMPLE);
  color = pow(color, vec3(1.0 / 2.2));

  if (DEBUG_OVERLAY) {
    mat4 scene_to_clip_xform =
        perspectiveTransform(CAMERA_YFOV, iResolution.z, 1e-3, 1e+3) *
        inverse(camera_xform);
    vec2 AB = iResolution.xy / 2.0;
    mat3 ndc_to_frag_xform = mat3(
        AB.x,  0.0, 0.0,
         0.0, AB.y, 0.0,
        AB.x, AB.y, 1.0);
    vec4 overlay_color = Overlay_coordinateAxisGrid(
        frag_coord, scene_to_clip_xform, ndc_to_frag_xform, 0.4);
    color = overlay_color.w * color + overlay_color.xyz;
  }

  frag_color = vec4(color, 1.0);
}


float smoothCoverage(float signed_distance, float width) {
  return 1.0 - smoothstep(0.0, 1.0, signed_distance / width + 0.5);
}

vec3 easyColor(float t) {
  float s = fract(sin(t * 123456.789) * 123456.789);
  vec3 v = vec3(0.0, 1.0, 2.0) / 3.0;
  vec3 c = 0.5 + 0.5 * cos(2.0 * M_PI * (s - v));
  c = smoothstep(vec3(-0.2), vec3(0.8), c);
  return c;
}

void mainImage_2d(out vec4 frag_color, vec2 frag_coord) {
  // "window -> scene" transform
  float xform_s = (BBOX_Y[1] - BBOX_Y[0]) / iResolution.y;
  vec2 xform_t = vec2(
      CENTER.x - (CENTER.y - BBOX_Y[0]) * iResolution.z,
      BBOX_Y[0]);

  {
    bool activated, down;
    vec2 last_click_pos, last_down_pos;
    getMouseState(iMouse, activated, down, last_click_pos, last_down_pos);
  }

  vec2 p = frag_coord * xform_s + xform_t;
  bool mouse_down = iMouse.z > 0.5;

  vec3 color = OZN.xxx;
  {
    SceneInfo info = getSceneSdf_2d(p);
    float fac = smoothCoverage(info.t, AA * xform_s);
    vec3 c = easyColor(info.id);
    color = mix(color, c, fac);
  }

  {
    //
    // Coordinate system
    //
    {
      // Grid
      float step = 1.0 / 2.0;
      float w = 1.0 * xform_s;
      float sd = 1e30;
      sd = min(sd, SdfOp_isoline(p.x, step, w));
      sd = min(sd, SdfOp_isoline(p.y, step, w));
      float fac = smoothCoverage(sd, AA * xform_s);
      color = mix(color, vec3(0.0), 0.2 * fac);
    }
    {
      // Axis
      float w = 1.0 * xform_s;
      float sd = 1e30;
      sd = min(sd, abs(p.x) - w / 2.0);
      sd = min(sd, abs(p.y) - w / 2.0);
      float fac = smoothCoverage(sd, AA * xform_s);
      color = mix(color, vec3(0.0), fac);
    }
  }

  frag_color = vec4(color, 1.0);
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // mainImage_2d(frag_color, frag_coord);
  mainImage_3d(frag_color, frag_coord);
}
