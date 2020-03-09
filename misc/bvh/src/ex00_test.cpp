#include <set>
#include <algorithm>

#include <catch2/catch.hpp>

#include "utils/format.hpp"
#include "utils/geometry.hpp"
#include "utils/ply.hpp"
#include "utils/bvh.hpp"
#include "utils/renderer.hpp"


TEST_CASE("format") {
  REQUIRE(utils::format("x: %d, y: %d", 1, 2) == "x: 1, y: 2");
  REQUIRE(utils::format("%s", utils::fvec3(1.0, 2.0, 3.0)) == "[1.000, 2.000, 3.000]");
  REQUIRE(utils::format("%s", utils::bbox3{{1.0, 2.0, 3.0}, {4.0, 5.0, 6.0}}) == "[[1.000, 2.000, 3.000], [4.000, 5.000, 6.000]]");
}


TEST_CASE("loadPly") {
  using std::string, std::vector;

  string filename = string(CMAKE_SOURCE_DIR) + "/data/bunny/reconstruction/bun_zipper_res4.ply";
  vector<utils::fvec3> vertices;
  vector<utils::uvec3> indices;
  utils::loadPly(filename, vertices, indices);

  REQUIRE(vertices.size() == 453);
  REQUIRE(indices.size() == 948);
}


TEST_CASE("Bvh-simple") {
  using std::string, std::vector;
  using namespace utils;

  // small triangle for each cube corner
  vector<fvec3> tri = {
    {0.1,   0,   0},
    {  0, 0.1,   0},
    {  0,   0, 0.1},
  };
  vector<fvec3> vertices;
  vector<uvec3> indices;
  for (auto x : vector<float>{-1, 1}) {
    for (auto y : vector<float>{-1, 1}) {
      for (auto z : vector<float>{-1, 1}) {
        auto i = (uint32_t)vertices.size();
        indices.push_back({i, i + 1, i + 2});
        vertices.push_back(fvec3{x, y, z} + tri[0]);
        vertices.push_back(fvec3{x, y, z} + tri[1]);
        vertices.push_back(fvec3{x, y, z} + tri[2]);
      }
    }
  }
  {
    Bvh bvh = Bvh::create(vertices, indices, 8);
    REQUIRE(bvh.primitives.size() == 8);
    REQUIRE(bvh.nodes.size() == 1);
  }
  {
    Bvh bvh = Bvh::create(vertices, indices, 4);
    REQUIRE(bvh.nodes.size() == 1 + 2);
  }
  {
    Bvh bvh = Bvh::create(vertices, indices, 2);
    REQUIRE(bvh.nodes.size() == 1 + 2 + 4);
  }

  Bvh bvh = Bvh::create(vertices, indices, 2);
  fvec3 ray_orig = fvec3(1, 1, 1) * 2.0f;
  fvec3 ray_dir = -glm::normalize(fvec3(1, 1, 1));
  float hit_t;
  uint32_t hit_primitive;
  bool hit = bvh.rayIntersect(ray_orig, ray_dir, 1e30, /*out*/ hit_t, hit_primitive);
  REQUIRE(hit);
  REQUIRE(hit_primitive == 7);
}

TEST_CASE("Bvh-bunny") {
  using std::string, std::vector;
  using namespace utils;

  string filename = string(CMAKE_SOURCE_DIR) + "/data/bunny/reconstruction/bun_zipper_res4.ply";
  vector<fvec3> vertices;
  vector<uvec3> indices;
  loadPly(filename, vertices, indices);
  Bvh bvh = Bvh::create(vertices, indices);
  REQUIRE(bvh.primitives.size() == 948);

  // Small validation of constructed bvh
  {
    auto first = bvh.primitives.begin();
    auto last  = bvh.primitives.end();
    std::set<uint32_t> unique_primitives{first, last};

    // no duplicate
    REQUIRE(bvh.primitives.size() == unique_primitives.size());

    // list [0, 948)
    REQUIRE(std::all_of(first, last, [](auto i){ return 0 <= i && i < 948; }));
  }
  {
    bool correct_containment = true;
    for (auto i = 0; i < bvh.nodes.size(); i++) {
      auto& node = bvh.nodes[i];
      if (node.isLeaf()) {
        for (auto j = 0; j < node.num_primitives; j++) {
          uint32_t prim = bvh.primitives[node.begin + j];
          Triangle tri = getTriangle(vertices, indices, prim);
          correct_containment &= node.bbox.contains(tri.bbox());
          // REQUIRE(node.bbox.contains(tri.bbox()));
          // print("[debug:contains] node:%d -> tri:%d\n", i, prim);
          // print("[debug:contains] node.bbox: %s\n", node.bbox);
          // print("[debug:contains] tri.bbox:  %s\n", tri.bbox());
        }
      } else {
        BvhNode& l = bvh.nodes[node.begin + 0];
        BvhNode& r = bvh.nodes[node.begin + 1];
        correct_containment &= node.bbox.contains(l.bbox);
        correct_containment &= node.bbox.contains(r.bbox);
        // REQUIRE(node.bbox.contains(l.bbox));
        // REQUIRE(node.bbox.contains(r.bbox));
        // print("[debug:contains] node:%d -> node:%d\n", i, node.begin + 0);
        // print("[debug:contains] node:%d -> node:%d\n", i, node.begin + 1);
        // print("[debug:contains] node.bbox: %s\n", node.bbox);
        // print("[debug:contains] l.bbox: %s\n", l.bbox);
        // print("[debug:contains] r.bbox: %s\n", r.bbox);
      }
    }
    REQUIRE(correct_containment);

    // // parent bbox containes child bbox
    // for (BvhNode& node : bvh.nodes) {
    //   if (node.isLeaf())
    //     continue;
    //   BvhNode& l  = bvh.nodes[node.begin + 0];
    //   BvhNode& r = bvh.nodes[node.begin + 1];
    //   // REQUIRE(node.bbox.contains(l.bbox));
    //   // REQUIRE(node.bbox.contains(r.bbox));
    // }
  }

  // Test Bvh::rayIntersect
  fvec3 ray_orig = fvec3(1, 1, 1) * 0.2f;
  fvec3 center = (bvh.nodes[0].bbox.bmin +  bvh.nodes[0].bbox.bmax) / 2.0f;
  fvec3 ray_dir = glm::normalize(center - ray_orig);
  float hit_t;
  uint32_t hit_primitive;
  bool hit = bvh.rayIntersect(ray_orig, ray_dir, 1e30, /*out*/ hit_t, hit_primitive);
  REQUIRE(hit);
  REQUIRE((0 <= hit_primitive && hit_primitive < 948));
}

TEST_CASE("Renderer-simple") {
  using std::string, std::vector, std::array;
  using namespace utils;

  // Octahedron (by scaling non-uniformly, we can completely predict resulting bvh)
  vector<fvec3> vertices = {
    {+3, 0, 0},
    { 0,+2, 0},
    { 0, 0,+1},
    { 0,-2, 0},
    { 0, 0,-1},
    {-3, 0, 0},
  };
  vector<uvec3> indices = {
    {0, 1, 2},
    {0, 2, 3},
    {0, 3, 4},
    {0, 4, 1},
    {5, 2, 1},
    {5, 3, 2},
    {5, 4, 3},
    {5, 1, 4},
  };
  Bvh bvh = Bvh::create(vertices, indices, 2);
  REQUIRE(bvh.primitives.size() == 8);

  // parent bbox containes child bbox
  {
    bool correct_containment = true;
    for (auto i = 0; i < bvh.nodes.size(); i++) {
      auto& node = bvh.nodes[i];
      if (node.isLeaf()) {
        for (auto j = 0; j < node.num_primitives; j++) {
          uint32_t prim = bvh.primitives[node.begin + j];
          Triangle tri = getTriangle(vertices, indices, prim);
          correct_containment &= node.bbox.contains(tri.bbox());
          // REQUIRE(node.bbox.contains(tri.bbox()));
          // print("[debug:contains] node:%d -> tri:%d\n", i, prim);
          // print("[debug:contains] node.bbox: %s\n", node.bbox);
          // print("[debug:contains] tri.bbox:  %s\n", tri.bbox());
        }
      } else {
        BvhNode& l = bvh.nodes[node.begin + 0];
        BvhNode& r = bvh.nodes[node.begin + 1];
        correct_containment &= node.bbox.contains(l.bbox);
        correct_containment &= node.bbox.contains(r.bbox);
        // REQUIRE(node.bbox.contains(l.bbox));
        // REQUIRE(node.bbox.contains(r.bbox));
        // print("[debug:contains] node:%d -> node:%d\n", i, node.begin + 0);
        // print("[debug:contains] node:%d -> node:%d\n", i, node.begin + 1);
        // print("[debug:contains] node.bbox: %s\n", node.bbox);
        // print("[debug:contains] l.bbox: %s\n", l.bbox);
        // print("[debug:contains] r.bbox: %s\n", r.bbox);
      }
    }
    REQUIRE(correct_containment);
  }
  return;

  fvec3 camera_loc = fvec3(1, 1, 1) * 5.0f;
  fvec3 lookat_loc = fvec3(0, 0, 0);
  fvec3 up_vec = {0, 1, 0};
  float yfov = 39.0f * M_PI / 180.0f;
  int w = 40, h = 40;
  auto rayIntersect = [&bvh](
      const fvec3& ray_orig, const fvec3& ray_dir, float ray_tmax,
      /*out*/ float& hit_t, uint32_t& hit_primitive, /*in*/ bool any_hit) {
    return bvh.rayIntersect(ray_orig, ray_dir, ray_tmax, hit_t, hit_primitive, any_hit);
  };
  RenderResult result = Renderer::render(camera_loc, lookat_loc, up_vec, yfov, w, h, rayIntersect);

  vector2<array<uint8_t, 3>> data; // rgb data
  data.resize(h, w);
  for (auto y = 0; y < h; y++) {
    for (auto x = 0; x < w; x++) {
      // Render hit
      // [debug]
      // {
      //   bool hit = result.hit(y, x);
      //   glm::u8vec3 rgb = glm::u8vec3(((uint8_t)hit) * 255);
      //   data(y, x) = {rgb[0], rgb[1], rgb[2]};
      //   continue;
      // }

      // Render normal
      if (!result.hit(y, x)) {
        data(y, x) = {128, 128, 128};
        continue;
      }
      Triangle tri = getTriangle(vertices, indices, result.primitive(y, x));
      fvec3 n = tri.normal();
      glm::u8vec3 rgb = glm::clamp((n * 0.5f + 0.5f) * 256.0f, fvec3(0), fvec3(255));
      data(y, x) = {rgb[0], rgb[1], rgb[2]};
    }
  }
}


TEST_CASE("Renderer-bunny") {
  using std::string, std::vector, std::array;
  using namespace utils;

  string filename = string(CMAKE_SOURCE_DIR) + "/data/bunny/reconstruction/bun_zipper_res4.ply";
  vector<fvec3> vertices;
  vector<uvec3> indices;
  loadPly(filename, vertices, indices);
  Bvh bvh = Bvh::create(vertices, indices, 8);

  fvec3 camera_loc = fvec3(1, 1, 1) * 0.2f;
  fvec3 lookat_loc = (bvh.nodes[0].bbox.bmin + bvh.nodes[0].bbox.bmax) / 2.0f;
  fvec3 up_vec = {0, 1, 0};
  float yfov = 39 * M_PI / 180;
  int w = 40, h = 40;
  auto rayIntersect = [&bvh](
      const fvec3& ray_orig, const fvec3& ray_dir, float ray_tmax,
      /*out*/ float& hit_t, uint32_t& hit_primitive, /*in*/ bool any_hit) {
    return bvh.rayIntersect(ray_orig, ray_dir, ray_tmax, hit_t, hit_primitive, any_hit);
  };
  RenderResult result = Renderer::render(camera_loc, lookat_loc, up_vec, yfov, w, h, rayIntersect);

  vector2<array<uint8_t, 3>> data; // rgb data
  data.resize(h, w);
  for (auto y = 0; y < h; y++) {
    for (auto x = 0; x < w; x++) {
      // Render hit
      // {
      //   bool hit = result.hit(y, x);
      //   glm::u8vec3 rgb = glm::u8vec3(((uint8_t)hit) * 255);
      //   data(y, x) = {rgb[0], rgb[1], rgb[2]};
      //   continue;
      // }

      // Render normal
      if (!result.hit(y, x)) {
        data(y, x) = {0, 0, 0};
        continue;
      }
      Triangle tri = getTriangle(vertices, indices, result.primitive(y, x));
      fvec3 n = tri.normal();
      glm::u8vec3 rgb = glm::clamp((n * 0.5f + 0.5f) * 256.0f, fvec3(0), fvec3(255));
      data(y, x) = {rgb[0], rgb[1], rgb[2]};
    }
  }
}
