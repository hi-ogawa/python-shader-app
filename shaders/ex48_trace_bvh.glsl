//
// Ray trace BVH using offline-made BVH data as SSBO
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: file
      # data: shaders/data/bunny.node.bin
      data: shaders/data/dragon2.node.bin

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

layout (std430, binding = 0) buffer MyBlock {
  BvhNode_ALIGNED b_bvh_nodes[];
};

// NOTE: Unfortunately, we need to hard code `b_bvh_nodes` since
//       glsl allows variable length array only for SSBO
bool intersect(Ray ray, out float hit_t, out uint hit_node) {
  bool hit = false;

  // This static array is actually unrolled as N variables
  // (e.g. when stack[64], Intel's SIMD16 compilation fails.)
  // So, we make smaller stack than the necessary bound `stack[64]`.
  const int BVH_STACK_LIMIT = 32;
  uint stack[BVH_STACK_LIMIT];

  // Push root node index
  int stack_top = 0;
  stack[stack_top] = 0u;

  while (0 <= stack_top) {
    // Too-deep exception as no hit
    if (BVH_STACK_LIMIT <= stack_top) {
      break;
    }

    uint node_idx = stack[stack_top];
    BvhNode node = BvhNode_fromAligned(b_bvh_nodes[node_idx]);
    stack_top--;

    bool hit_bbox;
    float hit_bbox_t;
    hit_bbox = Bbox_intersect(node.bbox, ray, hit_bbox_t);
    if (!hit_bbox) { continue; }

    if (BvhNode_isLeaf(node)) {
      hit = true;
      hit_node = node_idx;
      ray.tmax = hit_t = hit_bbox_t;
      continue;
    }

    stack_top++;
    stack[stack_top] = node.begin;
    stack_top++;
    stack[stack_top] = node.begin + 1u;
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
  Bbox root_bbox = BvhNode_fromAligned(b_bvh_nodes[0]).bbox;
  CAMERA_LOOKAT = Bbox_center(root_bbox);

  // Setup camera and generate ray
  Ray ray;
  generateRay(frag_coord, ray);

  // Intersect bvh
  float hit_t;
  uint hit_node;
  bool hit = intersect(ray, /*out*/ hit_t, hit_node);

  // Shade based on hit position
  vec3 color = vec3(0.0);
  if (hit) {
    vec3 p = ray.o + hit_t * ray.d;
    color = (p - root_bbox.bmin) / (root_bbox.bmax - root_bbox.bmin);
  }

  frag_color = vec4(color, 1.0);
}
