//
// Explore point group instancing modifier
//

#include "common_v0.glsl"
const vec3 OZN = vec3(1.0, 0.0, -1.0);

float AA = 2.0;
bool DEBUG_NORMAL = false;

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
vec3  CAMERA_LOC =    vec3(1.0, 0.5, 2.0) * 7.0;
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

vec3 SdfMod_translate2dBounded(
    vec3 p, vec2 XZ, vec2 n0_xz, vec2 n1_xz, out vec2 id) {
  vec2 q = p.xz / XZ;
  vec2 qc = clamp(q, n0_xz, n1_xz);
  id = floor(q + 0.5);
  p.xz = ((fract(qc + 0.5) - 0.5) + (q - qc)) * XZ;
  return p;
}

// instancing on tetrahedron faces (i.e. tetrahedron vertices)
vec3 SdfMod_tetrahedron(vec3 p, out float id) {
  // Construction based on four corners of cube
  const vec3 v0 = OZN.zzz;
  const vec3 v1 = OZN.xxz;
  const vec3 v2 = OZN.zxx;
  const vec3 v3 = OZN.xzx;
  const vec3 n1 = cross(v1, v2);
  const vec3 n2 = cross(v2, v3);
  const vec3 n3 = cross(v3, v1);
  const vec3 m1 = cross(v0, v1);
  const vec3 m2 = cross(v0, v2);
  const vec3 m3 = cross(v0, v3);
  // TODO: possible to go without branches and just use single rotate3
  bool b1 = dot(p, n1) > 0.0;
  bool b2 = dot(p, n2) > 0.0;
  bool b3 = dot(p, n3) > 0.0;
  bool c1 = dot(p, m1) > 0.0;
  bool c2 = dot(p, m2) > 0.0;
  bool c3 = dot(p, m3) > 0.0;
  if (b1 && b2 && b3) {
    // Here no-op. other three cases will be wrapped to this space.
    id = 0.0;
  } else
  if (!b1 && !c1 && c2) {
    p.zx = rotate2(M_PI) * p.zx;
    id = 1.0;
  } else
  if (!b2 && !c2 && c3) {
    p.xy = rotate2(M_PI) * p.xy;
    id = 2.0;
  } else
  if (!b3 && !c3 && c1) {
    p.yz = rotate2(M_PI) * p.yz;
    id = 3.0;
  }
  return p;
}

// Instancing on octahedron faces (i.e. cube vertices)
vec3 SdfMod_cube(vec3 p, out float id) {
  id = dot(max(vec3(0.0), sign(p)), vec3(4.0, 2.0, 1.0));
  return abs(p);
}

// Instancing on cube faces (i.e. octahedron vertices)
vec3 SdfMod_octahedron(vec3 p, out float id) {
  const vec3 n1 = OZN.xxy;
  const vec3 n2 = OZN.xzy;
  const vec3 n3 = OZN.yxx;
  const vec3 n4 = OZN.yxz;
  const vec3 n5 = OZN.xyx;
  const vec3 n6 = OZN.zyx;
  const bool b1 = dot(p, n1) > 0.0;
  const bool b2 = dot(p, n2) > 0.0;
  const bool b3 = dot(p, n3) > 0.0;
  const bool b4 = dot(p, n4) > 0.0;
  const bool b5 = dot(p, n5) > 0.0;
  const bool b6 = dot(p, n6) > 0.0;
  if ( b1 &&  b2 &&  b5 && !b6) {
    // no-op
    id = 0.0;
  } else
  if (!b1 && !b2 && !b5 &&  b6) {
    // z: +pi
    p.xy = rotate2(M_PI) * p.xy;
    id = 1.0;
  } else
  if ( b3 &&  b4 &&  b1 && !b2) {
    // z: -pi/2
    p.xy = rotate2(- M_PI / 2.0) * p.xy;
    id = 2.0;
  } else
  if (!b3 && !b4 && !b1 &&  b2) {
    // z: +pi/2
    p.xy = rotate2(+ M_PI / 2.0) * p.xy;
    id = 3.0;
  } else
  if ( b5 &&  b6 &&  b3 && !b4) {
    // y: +pi/2
    p.zx = rotate2(+ M_PI / 2.0) * p.zx;
    id = 4.0;
  } else
  if (!b5 && !b6 && !b3 &&  b4) {
    // y: -pi/2
    p.zx = rotate2(- M_PI / 2.0) * p.zx;
    id = 5.0;
  }
  return p;
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

float SDF_lineSegment(vec3 p, vec3 v, float t0, float t1) {
  // assert |v| = 1
  float t = dot(p, v);
  float tb = clamp(t, t0, t1);
  return distance(p, tb * v);
}

float SDF_triangle(vec3 p, vec3 v1, vec3 v2, vec3 v3) {
  vec3 u1 = v2 - v1;
  vec3 u2 = v3 - v2;
  vec3 u3 = v1 - v3;
  vec3 n  = cross(u1, -u3);
  vec3 w1 = cross(n, u1);
  vec3 w2 = cross(n, u2);
  vec3 w3 = cross(n, u3);
  vec3 q1 = p - v1;
  vec3 q2 = p - v2;
  vec3 q3 = p - v3;
  float t1 = dot(q1, w1);
  float t2 = dot(q2, w2);
  float t3 = dot(q3, w3);
  bool closest_to_face = t1 > 0.0 && t2 > 0.0 && t3 > 0.0;
  float dn = abs(dot(q1, n)) / length(n);
  float d1 = SDF_lineSegment(q1, normalize(u1), 0.0, length(u1));
  float d2 = SDF_lineSegment(q2, normalize(u2), 0.0, length(u2));
  float d3 = SDF_lineSegment(q3, normalize(u3), 0.0, length(u3));
  float d = min(min(d1, d2), d3);
  return closest_to_face ? dn : d;
}

//
// Scene definition
//

// Misc container
struct SceneInfo {
  float t;  // signed distance, 1d ray coordinate, etc..
  float id; // id associated with state t
};

float kIdChecker1 = 0.0;
float kIdChecker2 = 1.0;
float kIdOtherMin = 10.0;

SceneInfo mergeSceneInfo(SceneInfo info, float t, float id) {
  info.id = info.t < t ? info.id : id;
  info.t  = info.t < t ? info.t  : t ;
  return info;
}

SceneInfo mainSdf(vec3 p) {
  SceneInfo ret;
  ret.t = RAY_MAX_T;
  {
    // Ground by repeating thin boxes
    float size = 0.42;
    float depth = 0.05;
    vec2 XZ = 1.0 * OZN.xx;
    float n = 3.0;
    vec2 id;
    vec3 q = SdfMod_translate2dBounded(p, XZ, -n * OZN.xx, n * OZN.xx, id);
    float sd = Sdf_box(q, size * OZN.xyx);
    sd = SdfOp_deepen(sd, depth);
    // ret = mergeSceneInfo(ret, sd, mod(id.x + id.y, 2.0) == 0.0 ? kIdChecker1 : kIdChecker2);
  }
  {
    // Cube instancing demo
    float id;
    vec3 q = SdfMod_cube(p, id);
    vec3 loc = 1.0 * OZN.xxx;
    float r = 1.0;
    float sd = Sdf_sphere(q - loc, r);
    // ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__) + id * 7.0);
  }
  {
    // Octahedron instancing demo
    float id;
    vec3 q = SdfMod_octahedron(p, id);
    vec3 loc = 2.0 * OZN.xyy;
    float r = 1.0;
    float sd = Sdf_sphere(q - loc, r);
    // ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__) + id * 7.0);
  }
  {
    // Octahedron instancing demo 2
    // - construct rhombic dodecahedron
    float id;
    vec3 q = SdfMod_octahedron(p, id);
    vec3 loc = 1.0 * OZN.xyy;
    float t = 1.0 / 4.0 * iTime;
    float h = smoothstep(0.0, 1.0, abs(mod(t, 2.0) - 1.0));
    float depth = 0.04;
    // TODO: optimize 4 triangles
    float sd1 = SDF_triangle(q - loc, h * OZN.xyy, OZN.yxx, OZN.yxz) - depth;
    float sd2 = SDF_triangle(q - loc, h * OZN.xyy, OZN.yxz, OZN.yzz) - depth;
    float sd3 = SDF_triangle(q - loc, h * OZN.xyy, OZN.yzz, OZN.yzx) - depth;
    float sd4 = SDF_triangle(q - loc, h * OZN.xyy, OZN.yzx, OZN.yxx) - depth;
    float sd = min(min(sd1, sd2), min(sd3, sd4));
    ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__) + id * 7.0);
  }
  {
    // Tetrahedron instancing demo 1
    float id;
    vec3 q = SdfMod_tetrahedron(p, id);
    vec3 loc = 1.0 * OZN.xxx;
    float r = 1.0;
    float sd = Sdf_sphere(q - loc, r);
    // ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__) + id);
  }
  {
    // Tetrahedron instancing demo 2
    float id1, id2;
    vec3 q1 = SdfMod_tetrahedron(p, id1);
    vec3 q2 = SdfMod_tetrahedron(q1 - 1.0 * OZN.xxx, id2);
    float sd = Sdf_sphere(q2 - 0.5 * OZN.xxx, 0.5);
    // ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__) + id1 * 12.34 + id2 * 34.56);
  }
  {
    // Tetrahedron instancing demo 3
    // - construct tetrahedron by instancing single triangle
    vec3 loc1 = 2.5 * OZN.yxy;
    mat3 rot1 = rotate3(0.5 * M_PI * OZN.yxy);
    float id;
    vec3 q = SdfMod_tetrahedron(rot1 * p - loc1, id);
    vec3 loc2 = 0.1 * OZN.xxx;
    float depth = 0.1;
    float ud = SDF_triangle(q - loc2, OZN.xxz, OZN.zxx, OZN.xzx);
    float sd = SdfOp_deepen(ud, depth);
    // ret = mergeSceneInfo(ret, sd, kIdOtherMin + float(__LINE__) + id * 12.34);
  }
  return ret;
}


//
// Shading
//

vec3 shadeSurface(vec3 p, vec3 normal, vec3 ray_orig, vec3 ray_dir, SceneInfo info) {
  vec3 base_color = vec3(1.0);
  if (info.id == kIdChecker1) {
    base_color = OZN.yxx;
  }
  if (info.id == kIdChecker2) {
    base_color = OZN.yxx * 0.2;
  }
  if (info.id >= kIdOtherMin) {
    float t = info.id - kIdOtherMin;
    base_color = Quick_color(Quick_hash(t, 123456.0));
  }

  // [Debug] normal
  if (DEBUG_NORMAL) {
    return (0.5 + 0.5 * normal);
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
  float d = RM_NORMAL_DELTA;
  float dx_sdf = mainSdf(p + d * OZN.xyy).t - mainSdf(p - d * OZN.xyy).t;
  float dy_sdf = mainSdf(p + d * OZN.yxy).t - mainSdf(p - d * OZN.yxy).t;
  float dz_sdf = mainSdf(p + d * OZN.yyx).t - mainSdf(p - d * OZN.yyx).t;
  return normalize(vec3(dx_sdf, dy_sdf, dz_sdf));
}

SceneInfo rayMarch(vec3 orig, vec3 dir) {
  SceneInfo result;
  result.t = RAY_MAX_T;

  float t = 0.0;
  for (int i = 0; i < RM_MAX_ITER; i++) {
    SceneInfo step = mainSdf(orig + t * dir);
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
