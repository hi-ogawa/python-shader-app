#pragma once

#include <cstdio>

#include <vector>
#include <string>
#include <deque>

#include "format.hpp"
#include "geometry.hpp"


namespace utils {

using std::vector;


struct BvhNode {
  bbox3 bbox;  // 4bytes (float) * 3 * 2 = 24 bytes

  // this index refers to
  // - Bvh::primitives when `isLeaf`
  // - Bvh::nodes      when NOT `isLeaf`
  uint32_t begin;

  // num_primitives > 0  =>  isLeaf
  uint8_t num_primitives;

  // 0: x, 1: y, 2: z  (used only when NOT `isLeaf`)
  uint8_t axis;

  bool isLeaf() { return num_primitives > 0; }
};
static_assert(sizeof(BvhNode) == 32, "Expect BvhNode is exactly 32 bytes");


struct Bvh {
  const vector<fvec3>* vertices;
  const vector<uvec3>* indices;
  vector<uint32_t> primitives;
  vector<BvhNode> nodes;
  uint8_t max_primitive;

  //
  // Some relations
  //
  // - "primitives" refers to index of "indices"
  //     #indices = #prims
  // - by definition
  //     #nodes = #leafs + #internals
  // - each leaf node has at most "max_primitive"
  //     #prims <= max_prims * #leafs
  // - each leaf node has at least one primitive
  //     #leafs <= #prims
  // - "nodes" is binary tree
  //     #leafs  =  2 * #internals - (#internals - 1)  =  #internals + 1  ~~>
  //     #nodes  =  2 * #leafs + 1  <=  2 * #prims + 1
  //

  bool rayIntersect(
      const fvec3& ray_orig, const fvec3& ray_dir, float ray_t_max,
      /*out*/ float& hit_t, uint32_t& hit_primitive,
      bool any_hit = false);

  static Bvh create(
      const vector<fvec3>& vertices, const vector<uvec3>& indices,
      const uint8_t max_primitive = 2);

  static void splitPrimitives(
      uint32_t begin, uint32_t end, const vector<fvec3>& centers, const vector<bbox3>& bboxes,
      /*inout*/ vector<uint32_t>& primitives,
      /*out*/ uint8_t& axis, uint32_t& middle, bbox3& bbox_begin, bbox3& bbox_end);
};


void Bvh::splitPrimitives(
    uint32_t begin, uint32_t end, const vector<fvec3>& centers, const vector<bbox3>& bboxes,
    /*inout*/ vector<uint32_t>& primitives,
    /*out*/ uint8_t& axis, uint32_t& middle, bbox3& bbox_begin, bbox3& bbox_end) {
  // NOTE: primitives within [begin, end) will be shuffled

  // Choose split axis and position by
  // "the middel" of "the longest axis" of "the bbox" of "triangle centers"
  bbox3 cbbox;
  for (auto p = begin; p < end; p++) {
    fvec3 c = centers[primitives[p]];
    bbox3 bb{c, c};
    if (p == begin)
      cbbox = bb;
    cbbox = bbox3::opUnion(cbbox, bb);
  }
  axis = opArgMax(cbbox.bmax - cbbox.bmin);

  // If such split axis is too small, we simply split them half
  if (std::abs(cbbox.bmax[axis] - cbbox.bmin[axis]) < 1e-7) {
    middle = (begin + end) / 2;
    for (auto p = begin; p < middle; p++) {
      bbox3 bb = bboxes[primitives[p]];
      if (p == begin)
        bbox_begin = bb;
      bbox_begin = bbox3::opUnion(bbox_begin, bb);
    }
    for (auto p = middle; p < end; p++) {
      bbox3 bb = bboxes[primitives[p]];
      if (p == middle)
        bbox_end = bb;
      bbox_end = bbox3::opUnion(bbox_end,   bb);
    }
    return;
  }

  // Partition by (-oo, boundary) and [boundary, -oo)
  float boundary = (cbbox.bmax[axis] + cbbox.bmin[axis]) / 2;
  uint32_t curr_beg = begin;  // increment during loop
  uint32_t curr_end = end;    // decrement during loop
  for (; curr_beg < curr_end;) {
    uint32_t curr_prim = primitives[curr_beg];
    fvec3 center = centers[curr_prim];
    bbox3 bbox = bboxes[curr_prim];
    if (center[axis] < boundary) {
      if (curr_beg == begin)
        bbox_begin = bbox;
      bbox_begin = bbox3::opUnion(bbox_begin, bbox);
      curr_beg++;
    } else {
      if (curr_end == end)
        bbox_end = bbox;
      bbox_end = bbox3::opUnion(bbox_end, bbox);
      curr_end--;
      primitives[curr_beg] = primitives[curr_end];
      primitives[curr_end] = curr_prim;
    }
  }
  middle = curr_end;
}


Bvh Bvh::create(
    const vector<fvec3>& vertices, const vector<uvec3>& indices,
    const uint8_t max_primitive) {
  assert(max_primitive >= 1);

  // Result data
  vector<uint32_t> primitives;
  vector<BvhNode> nodes;

  // Intermidiate data for `splitPrimitives`
  vector<fvec3> centers;
  vector<bbox3> bboxes;

  // Initialize various containers and initial bbox
  bbox3 root_bbox;
  size_t num_prims = indices.size();
  primitives.resize(num_prims);
  centers.resize(num_prims);
  bboxes.resize(num_prims);
  nodes.reserve(2 * num_prims + 1); // see "Some relations" above

  for (auto i = 0; i < num_prims; i++) {
    primitives[i] = i;
    Triangle tri = getTriangle(vertices, indices, i);
    centers[i] = tri.centroid();
    bboxes[i] = tri.bbox();
    if (i == 0)
      root_bbox = bboxes[i];
    root_bbox = bbox3::opUnion(root_bbox, bboxes[i]);
  }

  //
  // Iteratively split nodes (TmpNodes) until leaf nodes have at most "max_primitive"
  //

  // TmpNode represents "possibly-to-be-splitted" leaf nodes
  // (BvhNode is not directly reused because `num_primitive` is uint8_t for 32bytes restriction)
  struct TmpNode {
    // node_idx refers to already allocated entry in `nodes`
    uint32_t node_idx;

    // TODO: see if having bbox calculated like now is really worth it
    bbox3 bbox;

    // where children primitives begin and end
    uint32_t begin;
    uint32_t end;
  };

  // Queue root node
  std::deque<TmpNode> queue;
  queue.push_back({ .node_idx = 0, .bbox = root_bbox, .begin = 0, .end = (uint32_t)num_prims });
  nodes.emplace_back(); // allocate for node_idx = 0

  while (!queue.empty()) {
    TmpNode tmp_node = queue.front();  queue.pop_front();
    BvhNode& node = nodes[tmp_node.node_idx];

    // Whichever case 1 or 2 we go, BvhNode.bbox is same.
    node.bbox = tmp_node.bbox;

    //
    // Case 1. When constraint is satisfied, construct "Leaf" BvhNode from TmpNode
    //         (i.e. TmpNode ~~> "Leaf" BvhNode)
    if (tmp_node.end - tmp_node.begin <= max_primitive) {
      node.bbox = tmp_node.bbox;
      node.begin = tmp_node.begin;
      node.num_primitives = tmp_node.end - tmp_node.begin;
      continue;
    }

    //
    // Case 2. Otherwise split TmpNode and construct "Internal" BvhNode
    //         (i.e. TmpNode ~~> "Internal" BvhNode x 1 + TmpNode x 2)
    uint8_t axis; uint32_t middle;
    bbox3 bbox_begin, bbox_end;
    splitPrimitives(
        tmp_node.begin, tmp_node.end, centers, bboxes, /*inout*/ primitives,
        /*out*/ axis, middle, bbox_begin, bbox_end);
    // print("[debug:bvh] %s\n", node.bbox);
    // print("[debug:bvh] l: %s\n", bbox_begin);
    // print("[debug:bvh] r: %s\n", bbox_end);

    // TmpNode x 2
    uint32_t size_now = nodes.size();
    queue.push_back({ .node_idx = size_now + 0, .bbox = bbox_begin, .begin = tmp_node.begin, .end = middle       });
    queue.push_back({ .node_idx = size_now + 1, .bbox = bbox_end,   .begin = middle,         .end = tmp_node.end });
    nodes.emplace_back(); // allocate for size_now + 0
    nodes.emplace_back(); // allocate for size_now + 1

    // "Internal" BvhNode
    node.axis = axis;
    node.begin = size_now;
  }

  nodes.shrink_to_fit();
  return Bvh{&vertices, &indices, primitives, nodes, max_primitive};
}


bool Bvh::rayIntersect(
    const fvec3& ray_orig, const fvec3& ray_dir, float ray_tmax,
    /*out*/ float& hit_t, uint32_t& hit_primitive, /*in*/ bool any_hit) {

  // Use hit_t as tmax during loop
  bool hit = false;
  hit_t = ray_tmax;

  // `stack` holds `nodes` index to traverse
  vector<uint32_t> stack;
  stack.reserve(this->nodes.size()); // at most such size
  stack.push_back(0); // start from first node

  while (!stack.empty()) {
    uint32_t node_idx = stack.back();  stack.pop_back();
    BvhNode& node = this->nodes[node_idx];

    float t_bbox;
    bool hit_bbox = node.bbox.rayIntersect(ray_orig, ray_dir, hit_t, /*out*/ t_bbox);
    if (!hit_bbox) {
      continue;
    }

    if (!node.isLeaf()) {
      stack.push_back(node.begin);
      stack.push_back(node.begin + 1);
      continue;
    }

    for (auto i = 0; i < node.num_primitives; i++) {
      uint32_t prim = this->primitives[node.begin + i];
      Triangle tri = getTriangle(*(this->vertices), *(this->indices), prim);
      float t_tri;
      bool hit_tri = tri.rayIntersect(ray_orig, ray_dir, hit_t, /*out*/ t_tri);
      if (!hit_tri)
        continue;

      hit = hit_tri;
      hit_t = t_tri;
      hit_primitive = prim;
      if (any_hit)
        return true;
    }
  }

  return hit;
};


} // namespace utils
