#include <catch2/catch.hpp>

#include "utils/ply.hpp"
#include "utils/bvh.hpp"
#include "utils/renderer.hpp"


TEST_CASE("Bvh-bunny-benchmark") {
  using std::string, std::vector;

  {
    string filename = string(CMAKE_SOURCE_DIR) + "/data/bunny/reconstruction/bun_zipper_res4.ply";
    vector<utils::fvec3> vertices;
    vector<utils::uvec3> indices;
    utils::loadPly(filename, vertices, indices);

    BENCHMARK("bun_zipper_res4.ply - max_primitive = 2") {
      return utils::Bvh::create(vertices, indices, 2);
    };

    BENCHMARK("bun_zipper_res4.ply - max_primitive = 4") {
      return utils::Bvh::create(vertices, indices, 2);
    };

    BENCHMARK("bun_zipper_res4.ply - max_primitive = 8") {
      return utils::Bvh::create(vertices, indices, 2);
    };
  }

  {
    string filename = string(CMAKE_SOURCE_DIR) + "/data/bunny/reconstruction/bun_zipper_res3.ply";
    vector<utils::fvec3> vertices;
    vector<utils::uvec3> indices;
    utils::loadPly(filename, vertices, indices);

    BENCHMARK("bun_zipper_res3.ply - max_primitive = 2") {
      return utils::Bvh::create(vertices, indices, 2);
    };
  }

  {
    string filename = string(CMAKE_SOURCE_DIR) + "/data/bunny/reconstruction/bun_zipper_res2.ply";
    vector<utils::fvec3> vertices;
    vector<utils::uvec3> indices;
    utils::loadPly(filename, vertices, indices);

    BENCHMARK("bun_zipper_res2.ply - max_primitive = 2") {
      return utils::Bvh::create(vertices, indices, 2);
    };
  }

  {
    string filename = string(CMAKE_SOURCE_DIR) + "/data/bunny/reconstruction/bun_zipper.ply";
    vector<utils::fvec3> vertices;
    vector<utils::uvec3> indices;
    utils::loadPly(filename, vertices, indices);

    BENCHMARK("bun_zipper.ply - max_primitive = 2") {
      return utils::Bvh::create(vertices, indices, 2);
    };
  }
}
