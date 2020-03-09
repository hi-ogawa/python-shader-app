#pragma once

#include <fstream>

#include "common.hpp"
#include "format.hpp"
#include "geometry.hpp"

namespace utils {

using std::string, std::vector;

//
// ascii format .ply file loader
//

inline void loadPly(
    const string& filename,
    /*out*/ vector<fvec3>& vertices, vector<uvec3>& indices, bool debug = false) {

  std::ifstream ifs(filename);
  MY_ASSERT(ifs.is_open());

  // header data
  int num_verts = -1;
  int num_faces = -1;
  int end_header = -1;

  // parser states
  int line_num = 1;
  string line;

  // Parse header
  {
    for (; std::getline(ifs, line); line_num++) {
      if (line_num == 1) MY_ASSERT(line == "ply");
      if (line_num == 2) MY_ASSERT(line == "format ascii 1.0");
      if (num_verts == -1) {
        std::sscanf(line.c_str(), "element vertex %d", &num_verts);
      }
      if (num_faces == -1) {
        std::sscanf(line.c_str(), "element face %d", &num_faces);
      }
      if (line == "end_header") {
        end_header = line_num;
        break;
      }
    }
    if (debug) {
      print("[debug] num_verts: %d\n", num_verts);
      print("[debug] num_faces: %d\n", num_faces);
      print("[debug] end_header: %d\n", end_header);
    }
    MY_ASSERT(num_verts != -1);
    MY_ASSERT(num_faces != -1);
    MY_ASSERT(end_header != -1);
  }

  // Parse vertex data
  vertices.resize(num_verts);
  for (int i = 0; i < num_verts; i++) {
    MY_ASSERT(std::getline(ifs, line));
    auto& v = vertices[i];
    MY_ASSERT(std::sscanf(line.c_str(), "%f %f %f", &v[0], &v[1], &v[2]));
  }

  // Parse face data
  indices.resize(num_faces);
  for (int i = 0; i < num_faces; i++) {
    MY_ASSERT(std::getline(ifs, line));
    auto& v = indices[i];
    MY_ASSERT(std::sscanf(line.c_str(), "3 %d %d %d", &v[0], &v[1], &v[2]));
  }

  // Expect no data is left
  MY_ASSERT(!std::getline(ifs, line));
}


} // namespace utils
