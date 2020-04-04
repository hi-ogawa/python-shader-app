//
// Environment map projection (latlng, probe, cube)
// - texcoordLatLngEnvMap
// - texcoordPauldebevecProbeEnvMap
// - texcoordPauldebevecCrossEnvMap
//
// NOTE: interpolation artifact can be observed when mipmap is enabled
//

/*
%%config-start%%
samplers:
  - name: tex_latlng
    type: file
    file: shaders/images/hdrihaven/sunflowers_1k.hdr.png
    mipmap: false
    wrap: repeat
    filter: nearest
  - name: tex_probe
    type: file
    file: shaders/images/pauldebevec/galileo_probe.hdr.png
    mipmap: false
    wrap: repeat
    filter: nearest
  - name: tex_cross
    type: file
    file: shaders/images/pauldebevec/galileo_cross.hdr.png
    mipmap: false
    wrap: repeat
    filter: nearest

programs:
  - name: mainImage
    output: $default
    samplers: [tex_latlng, tex_probe, tex_cross]

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

#include "common_v0.glsl"
#include "utils/overlay_v0.glsl"
const vec3 OZN = vec3(1.0, 0.0, -1.0);

bool  FILE_PREVIEW = false;
float FILE_PREVIEW_SCALE = 0.5;
#define ENV_MAP_TYPE 1 // latlng: 0, probe: 1, cross: 2

float AA = 2.0;
bool  DEBUG_NORMAL = false;
bool  DEBUG_OVERLAY = true;
float DEBUG_OVERLAY_FAC = 0.6;

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
float CAMERA_YFOV = 60.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(1.0, 0.5, 2.0) * 6.0;
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

float Sdf_lineSegment(vec3 p, vec3 v, float t0, float t1) {
  // assert |v| = 1
  float t = dot(p, v);
  float s = clamp(t, t0, t1);
  return distance(p, s * v);
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
    // Move "eps" away from exact integer coordinate where color is discontinuous
    float eps = 0.01;
    vec3 size = vec3(2.0, 1.0, 2.0) * (1.0 - eps);
    vec3 loc  = - vec3(0.0, size.y, 0.0) - eps;
    float sd = Sdf_box(p - loc, size);
    ret = mergeSceneInfo(ret, sd, kIdGround);
  }
  {
    vec3 loc  = OZN.yxy;
    float r = 1.0;
    float sd = Sdf_sphere(p - loc, r);
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__));
  }
  return ret;
}


//
// Shading
//

float checker(vec3 p, vec3 dxdp, vec3 dydp) {
  vec3 q = sign(mod(p, 2.0) - 1.0);
  // Naive version ("separable" xor formula)
  // return 0.5 + 0.5 * q.x * q.y * q.z;

  // Approximate pixel coverage by box (reasonably over-estimate by abs)
  vec3 b = abs(dxdp) + abs(dydp);

  // Integrate 3d checker on the pixel coverage
  vec3 v0 = mod(p - b / 2.0, 2.0);
  vec3 v1 = mod(p + b / 2.0, 2.0);
  vec3 integrals = (abs(v1 - 1.0) - abs(v0 - 1.0)) / b;

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

// e.g. hdrihaven
vec2 texcoordLatLngEnvMap(vec3 dir) {
  vec3 rtp = sphericalCoordinate(dir.zxy);
  float theta = rtp.y;
  float phi = rtp.z;
  // Reorient so that original image's midde row goes like (+z, -x, -z, +x, -z)
  return vec2(
      1.0 - (mod(phi, 2.0 * M_PI) / (2.0 * M_PI)),
      1.0 - theta / M_PI);
}

// e.g. pauldebevec "probe" format
vec2 texcoordPauldebevecProbeEnvMap(vec3 dir) {
  vec3 rtp = sphericalCoordinate(vec3(dir.x, dir.y, -dir.z));
  float theta = rtp.y;
  float phi = rtp.z;
  return 0.5 + 0.5 * rotate2(phi) * vec2(theta / M_PI, 0.0);
}

// e.g. pauldebevec "cross" format
vec2 texcoordPauldebevecCrossEnvMap(vec3 dir) {
  vec3 d = abs(dir);
  float d_max = max(max(d.x, d.y), d.z);
  vec2 offset; // [0, 3) x [0, 4)

  // All cases will be rotated so that
  // "z = -1 plane projection" below will work

  // z = -1 plane
  if (d_max == d.z && dir.z < 0) {
    offset = vec2(1.0, 2.0);
  } else

  // z = +1 plane
  if (d_max == d.z && dir.z > 0) {
    offset = vec2(1.0, 0.0);
    dir.yz = rotate2(M_PI) * dir.yz;
  } else

  // x = -1 plane
  if (d_max == d.x && dir.x < 0) {
    offset = vec2(0.0, 2.0);
    dir.zx = rotate2(- M_PI / 2.0) * dir.zx;
  } else

  // x = +1 plane
  if (d_max == d.x && dir.x > 0) {
    offset = vec2(2.0, 2.0);
    dir.zx = rotate2(+ M_PI / 2.0) * dir.zx;
  } else

  // y = -1 plane
  if (d_max == d.y && dir.y < 0) {
    offset = vec2(1.0, 1.0);
    dir.yz = rotate2(+ M_PI / 2.0) * dir.yz;
    // return OZN.xx;
  } else

  // y = +1 plane
  if (d_max == d.y && dir.y > 0) {
    offset = vec2(1.0, 3.0);
    dir.yz = rotate2(- M_PI / 2.0) * dir.yz;
  }

  // z = -1 plane projection
  vec2 uv = dir.xy / -dir.z; // [-1, 1]^2
  uv = 0.5 + 0.5 * uv;       // [ 0, 1]^2
  uv += offset;              // [ 0, 3] x [0, 4]
  uv /= vec2(3.0, 4.0);      // [ 0, 1]^2
  return uv;
}

vec3 shadeEnvironment(vec3 ray_orig, vec3 ray_dir, sampler2D env_tex) {
  vec2 uv;
  #if   ENV_MAP_TYPE == 0
    uv = texcoordLatLngEnvMap(ray_dir);
  #elif ENV_MAP_TYPE == 1
    uv = texcoordPauldebevecProbeEnvMap(ray_dir);
  #elif ENV_MAP_TYPE == 2
    uv = texcoordPauldebevecCrossEnvMap(ray_dir);
  #endif
  return texture(env_tex, uv, 0).xyz;
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

vec3 singleSample(vec2 frag_coord, mat3 inv_view_xform, mat4 camera_xform, sampler2D env_tex) {
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
    color = shadeEnvironment(ray_orig, ray_dir, env_tex);
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

vec3 previewFile(vec2 frag_coord, sampler2D tex, vec4 mouse) {
  vec2 delta = vec2(0.0);
  {
    bool mouse_activated, mouse_down;
    vec2 last_click_pos, last_down_pos;
    getMouseState(mouse, mouse_activated, mouse_down, last_click_pos, last_down_pos);
    if (mouse_activated && mouse_down) {
      delta = last_down_pos - last_click_pos;
    }
  }
  ivec2 coord = ivec2(floor((frag_coord - delta) / FILE_PREVIEW_SCALE));
  vec3 color = texelFetch(tex, coord, 0).xyz;
  return color;
}

void mainImage(
    out vec4 frag_color, vec2 frag_coord,
    sampler2D latlng, sampler2D probe, sampler2D cross) {
  #if   ENV_MAP_TYPE == 0
    #define ENV_TEX latlng
  #elif ENV_MAP_TYPE == 1
    #define ENV_TEX probe
  #elif ENV_MAP_TYPE == 2
    #define ENV_TEX cross
  #endif

  //
  // File preview mode
  //
  if (FILE_PREVIEW) {
    vec3 color = previewFile(frag_coord, ENV_TEX, iMouse);
    frag_color = vec4(color, 1.0);
    return;
  }

  //
  // 3D mapped mode
  //
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
      color += singleSample(ms_frag_coord, inv_view_xform, camera_xform, ENV_TEX);
    }
  }
  color /= (AA * AA);
  color = pow(color, vec3(1.0 / 2.2));

  //
  // Coordinate overlay to debug mapping
  //
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
        frag_coord, scene_to_clip_xform, ndc_to_frag_xform, DEBUG_OVERLAY_FAC);
    color = overlay_color.w * color + overlay_color.xyz;
  }

  frag_color = vec4(color, 1.0);
}
