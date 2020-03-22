//
// Ray trace BVH using offline-made BVH data as SSBO
// (Load triangle data and shade by normal)
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: file
      data: shaders/data/dragon2.node.bin
  - type: ssbo
    params:
      binding: 1
      type: file
      data: shaders/data/dragon2.primitive.bin
  - type: ssbo
    params:
      binding: 2
      type: file
      data: shaders/data/dragon2.vertex.bin
      align16: 12
  - type: ssbo
    params:
      binding: 3
      type: file
      data: shaders/data/dragon2.index.bin
      align16: 12

samplers: []

programs:
  - name: mainImage
    samplers: []
    output: $default

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

#include "common_v0.glsl"

const vec3 OZN = vec3(1.0, 0.0, -1.0);


//
// Utilities
//

float reduceMax(vec3 v) {
  return max(v[0], max(v[1], v[2]));
}

float reduceMin(vec3 v) {
  return min(v[0], min(v[1], v[2]));
}

//
// Data structure
//

struct Bbox {
  vec3 bmin, bmax;
};

vec3 Bbox_center(Bbox self) {
  return (self.bmin + self.bmax) / 2.0;
}

// Cf. misc/bvh/src/utils/bvh.hpp
struct BvhNode {
  Bbox bbox;
  uint begin;
  uint num_primitives;
  uint axis;
};

bool BvhNode_isLeaf(BvhNode self) {
  return 0 < self.num_primitives;
}

// 16bytes aligned temporary struct for SSBO layout
struct BvhNode_ALIGNED {
  vec4 v0, v1;
};

BvhNode BvhNode_fromAligned(BvhNode_ALIGNED A) {
  BvhNode node;
  node.bbox.bmin = A.v0.xyz;
  node.bbox.bmax = vec3(A.v0.w, A.v1.xy);
  node.begin = floatBitsToUint(A.v1.z);
  uint tmp = floatBitsToUint(A.v1.w);
  node.num_primitives = (tmp >> (8u * 0u)) & 0xffu;
  node.axis = (tmp >> (8u * 1u)) & 0xffu;
  return node;
}


struct Ray {
  vec3 o, d;
  float tmax;
};

struct Intersection {
  vec3 p;
  vec3 n;
};

bool Bbox_intersect(Bbox self, Ray ray, out float hit_t) {
  // Interesect to six planes
  vec3 t0 = (self.bmin - ray.o) / ray.d;  // "negative" planes
  vec3 t1 = (self.bmax - ray.o) / ray.d;  // "positive" planes

  // Determine ray going in/out of parallel planes
  float t_in  = reduceMax(min(t0, t1));
  float t_out = reduceMin(max(t0, t1));

  hit_t = t_in;
  return (t_in < t_out) && 0.0 < t_out && ( // half-line crosses box (i.e. ray without tmax)
    (t_in < 0.0) ||                         // ray_orig is interior
    (t_in < ray.tmax)                       // ray_orig is outside but reaches box before tmax
  );
}

struct Triangle {
  vec3 vs[3];
};

bool Triangle_intersect(Triangle tri,
    Ray ray, out Intersection isect, out float hit_t) {
  vec3 vs[3] = tri.vs;
  vec3 u1 = vs[1] - vs[0];
  vec3 u2 = vs[2] - vs[0];

  vec3 n = cross(u1, u2);
  float ray_dot_n = dot(ray.d, n);

  // Check if seeing ccw face
  if (ray_dot_n >= 0) {
    return false;
  }

  // Check if ray intersects plane(v0, n)
  //   <(o + t d) - v0, n> = 0
  hit_t = dot(vs[0] - ray.o, n) / ray_dot_n;
  if (!(0 < hit_t && hit_t < ray.tmax)) {
    return false;
  }

  // Check if p is inside of triangle
  vec3 p = ray.o + hit_t * ray.d;
  mat2x3 A = mat2x3(u1, u2);
  mat3x2 AT = transpose(A);
  vec2 st = inverse(AT * A) * AT * (p - vs[0]);  // barycentric coord
  if (0 < st[0] && 0 < st[1] && st[0] + st[1] < 1) {
    isect.n = normalize(n);
    isect.p = p;
    return true;
  }
  return false;
}

//
// Global data as SSBO
//

// NOTE: Unfortunately, we need to hard code `Ssbo_bvh_nodes` in function since
//       glsl allows variable length array only for SSBO.
//       For such function, we prefix it as in `Global_xxx`.
layout (std430, binding = 0) buffer Ssbo0 {
  BvhNode_ALIGNED Ssbo_bvh_nodes[]; // align16
};

layout (std430, binding = 1) buffer Ssbo1 {
  uint Ssbo_primitives[]; // flat
};

layout (std140, binding = 2) buffer Ssbo2 {
  vec3 Ssbo_vertices[]; // align16
};

layout (std140, binding = 3) buffer Ssbo3 {
  uvec3 Ssbo_indices[]; // align16
};

void Global_getTriangle(uint primitive, out Triangle tri) {
  uvec3 index3 = Ssbo_indices[primitive];
  tri.vs[0] = Ssbo_vertices[index3[0]];
  tri.vs[1] = Ssbo_vertices[index3[1]];
  tri.vs[2] = Ssbo_vertices[index3[2]];
}

bool Global_Bvh_intersect(Ray ray, bool any_hit, out Intersection isect) {
  bool hit = false;

  // This static array is actually unrolled as N variables
  // (e.g. when stack[64], Intel's SIMD16 compilation fails.)
  // So, we make smaller stack than the necessary bound `stack[64]`.
  const int BVH_STACK_LIMIT = 24;
  uint stack[BVH_STACK_LIMIT];

  // Push root node index
  int stack_top = 0;
  stack[stack_top] = 0u;

  while (0 <= stack_top) {
    // Too-deep exception as no hit
    if (BVH_STACK_LIMIT <= stack_top) {
      break;
    }

    uint node_idx = stack[stack_top--];
    BvhNode node = BvhNode_fromAligned(Ssbo_bvh_nodes[node_idx]);

    bool hit_bbox;
    float hit_bbox_t;
    hit_bbox = Bbox_intersect(node.bbox, ray, hit_bbox_t);
    if (!hit_bbox) { continue; }

    // Go deeper for non-leaf nodes
    if (!BvhNode_isLeaf(node)) {
      // Traverse closer child first
      if (0 < ray.d[node.axis]) {
        stack[++stack_top] = node.begin + 1u;
        stack[++stack_top] = node.begin;
      } else {
        stack[++stack_top] = node.begin;
        stack[++stack_top] = node.begin + 1u;
      }
      continue;
    }

    // Traverse triangles for leaf nodes
    for (uint i = 0; i < node.num_primitives; i++) {
      uint primitive = Ssbo_primitives[node.begin + i];
      Triangle tri;
      Global_getTriangle(primitive, /*out*/ tri);

      bool hit_tri;
      float hit_tri_t;
      hit_tri = Triangle_intersect(tri, ray, /*out*/ isect, hit_tri_t);
      if (!hit_tri) { continue; }

      hit = true;
      ray.tmax = hit_tri_t;
      if (any_hit) { return true; }
    }
  }
  return hit;
};


//
// Camera setup routines
//

const float CAMERA_YFOV = 39.0 * M_PI / 180.0;
const vec3  CAMERA_LOC = vec3(-0.1, 0.3, 0.3);
vec3  CAMERA_LOOKAT = vec3(0.0, 0.0, 0.0);


mat4 getCameraTransform(vec4 mouse, vec2 resolution) {
  bool mouse_activated, mouse_down;
  vec2 last_click_pos, last_down_pos;
  getMouseState(mouse, mouse_activated, mouse_down, last_click_pos, last_down_pos);

  vec2 delta = vec2(0.0);
  if (mouse_activated && mouse_down) {
    delta += (last_down_pos - last_click_pos) / resolution;
  }
  return pivotTransform_v2(CAMERA_LOC, CAMERA_LOOKAT, 2.0 * M_PI * delta);
}

void generateRay(vec2 frag_coord, out Ray ray) {
  mat3 inv_view_xform = inverseViewTransform(CAMERA_YFOV, iResolution.xy);
  mat4 camera_xform = getCameraTransform(iMouse, iResolution.xy);
  vec3 ray_orig = vec3(camera_xform[3]);
  mat3 ray_xform = mat3(camera_xform) * mat3(OZN.xyy, OZN.yxy, -OZN.yyx) * inv_view_xform;

  ray.o = vec3(camera_xform[3]);
  ray.d = normalize(ray_xform * vec3(frag_coord, 1.0));
  ray.tmax = 1e30;
}


//
// Main
//

void mainImage(out vec4 frag_color, in vec2 frag_coord){
  // Use bbox center as lookat position
  Bbox root_bbox = BvhNode_fromAligned(Ssbo_bvh_nodes[0]).bbox;
  CAMERA_LOOKAT = Bbox_center(root_bbox);

  // Setup camera and generate ray
  Ray ray;
  generateRay(frag_coord, ray);

  // Intersect bvh
  Intersection isect;
  bool hit = Global_Bvh_intersect(ray, /*any_hit*/ false, /*out*/ isect);

  // Shade based on hit position
  vec3 color = vec3(0.0);
  if (hit) {
    // [position]
    // color = (isect.p - root_bbox.bmin) / (root_bbox.bmax - root_bbox.bmin);

    // [normal]
    color = 0.5 + 0.5 * isect.n;
  }

  frag_color = vec4(color, 1.0);
}
