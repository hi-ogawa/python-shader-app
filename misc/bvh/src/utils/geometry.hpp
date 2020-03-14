#pragma once

#include <array>
#include <ostream>

#include <glm/glm.hpp>

#include "common.hpp"
#include "format.hpp"


namespace utils {

//
// Geometry utilities (vec, bbox, Triangle)
//

using glm::fvec2, glm::fvec3, glm::fvec4,
      glm::uvec3, glm::u8vec3,
      glm::fmat3, glm::fmat4;


uint8_t opArgMax(const fvec3& v) {
  uint8_t ret = 0;
  for (int i = 1; i < 3; i++) {
    ret = v[i] < v[ret] ? ret : i;
  }
  return ret;
}

float opMinReduce(const fvec3& v) {
  return fminf(fminf(v[0], v[1]), v[2]);
}

float opMaxReduce(const fvec3& v) {
  return fmaxf(fmaxf(v[0], v[1]), v[2]);
}


struct bbox3 {
  fvec3 bmin, bmax;

  static bbox3 opUnion(const bbox3& b1, const bbox3& b2) {
    return bbox3{
        glm::min(b1.bmin, b2.bmin),
        glm::max(b1.bmax, b2.bmax),};
  }

  fvec3 center() {
    return (bmin + bmax) / 2.0f;
  }

  bool contains(const bbox3& other) {
    return
      opMinReduce(other.bmin - this->bmin) >= 0 &&
      opMinReduce(this->bmax - other.bmax) >= 0;
  }

  friend std::ostream& operator<<(std::ostream& os, const bbox3& bbox) {
    os << utils::format("[%s, %s]", bbox.bmin, bbox.bmax);
    return os;
  }

  bool rayIntersect(
      const fvec3& ray_orig, const fvec3& ray_dir, float ray_tmax,
      /*out*/ float& hit_t) {

    // Interesect to six planes
    fvec3 t0 = (this->bmin - ray_orig) / ray_dir;  // "negative" planes
    fvec3 t1 = (this->bmax - ray_orig) / ray_dir;  // "positive" planes

    // Determine ray going in/out of parallel planes
    float t_in  = opMaxReduce(min(t0, t1));
    float t_out = opMinReduce(max(t0, t1));

    hit_t = t_in;
    return (t_in < t_out) && 0 < t_out && ( // half-line crosses box (i.e. ray without tmax)
      (t_in < 0 ) ||                        // ray_orig is interior
      (t_in < ray_tmax)                     // ray_orig is outside but reaches box before tmax
    );
  }
};

struct Triangle {
  std::array<fvec3, 3> vs;

  fvec3 centroid() {
    return (vs[0] + vs[1] + vs[2]) / 3.0f;
  }

  bbox3 bbox() {
    using glm::min, glm::max;
    return bbox3{
        min(min(vs[0], vs[1]), vs[2]),
        max(max(vs[0], vs[1]), vs[2]),};
  }

  fvec3 normal() {
    using glm::cross, glm::normalize;
    return normalize(cross(vs[1] - vs[0], vs[2] - vs[0]));
  }

  bool rayIntersect(
      const fvec3& ray_orig, const fvec3& ray_dir, float ray_tmax,
      /*out*/ float& hit_t) {
    using glm::cross, glm::dot, glm::transpose, glm::inverse;

    fvec3 u1 = vs[1] - vs[0];
    fvec3 u2 = vs[2] - vs[0];
    fvec3 n = cross(u1, u2);
    float ray_dot_n = dot(ray_dir, n);

    // Check if seeing ccw face
    if (ray_dot_n >= 0)
      return false;

    // Check if ray intersects plane(v0, n)
    //   <(o + t d) - v0, n> = 0
    hit_t = dot(vs[0] - ray_orig, n) / ray_dot_n;
    if (!(0 < hit_t && hit_t < ray_tmax))
      return false;

    // Check if p is inside of triangle
    fvec3 p = ray_orig + hit_t * ray_dir;
    glm::fmat2x3 A = {u1, u2};
    glm::fmat3x2 AT = glm::transpose(A);
    fvec2 st = inverse(AT * A) * AT * (p - vs[0]);  // barycentric coord
    if (0 < st[0] && 0 < st[1] && st[0] + st[1] < 1)
      return true;

    return false;
  }
};


inline Triangle getTriangle(const std::vector<fvec3>& vertices, const std::vector<uvec3>& indices, uint32_t i) {
  uvec3 v012 = indices[i];
  return Triangle{vertices[v012[0]], vertices[v012[1]], vertices[v012[2]]};
}

// [0, W] x [0, H]  -->  [-X/2, X/2] x [-tan(yfov/2), tan(yfov/2)]
//   where X defined so that aspect ratio is preserved
inline fmat3 xformInvView(float yfov, float w, float h) {
  float half_y = glm::tan(yfov / 2.0);
  float half_x = (w / h) * half_y;
  float a = -half_x;
  float b = -half_y;
  float s = 2 * half_y / h;
  return glm::fmat3{
      s, 0, 0,
      0, s, 0,
      a, b, 1,};
}

inline fmat4 xformLookAt(fvec3 eye_loc, fvec3 lookat_loc, fvec3 up_vec) {
  // assert |up| = 1
  using glm::normalize, glm::cross;
  fvec3 z = normalize(eye_loc - lookat_loc);
  fvec3 x = - cross(z, up_vec);
  fvec3 y = cross(z, x);
  fvec3 t = eye_loc;
  return glm::fmat4{
      x[0], x[1], x[2], 0.0,
      y[0], y[1], y[2], 0.0,
      z[0], z[1], z[2], 0.0,
      t[0], t[1], t[2], 1.0,};
}

inline fmat3 xformZframe(fvec3 z) {
  // assert |z| = 1
  using glm::normalize, glm::cross, glm::abs;
  fvec3 x = cross(z, (abs(z.x) < 0.9) ? fvec3(1.0, 0.0, 0.0) : fvec3(0.0, 1.0, 0.0));
  x = normalize(x);
  fvec3 y = cross(z, x);
  return fmat3(x, y, z);
}


} // namespace utils


// Define "operator<<(..., fvec3)" within glm namespace so that "utils::toScalarOrString" in format.hpp can find it.
// (cf. http://clang.llvm.org/compatibility.html#dep_lookup)
namespace glm {

inline std::ostream& operator<<(std::ostream& os, const glm::fvec2& v) {
  os << utils::format("[%.3f, %.3f]", v[0], v[1]);
  return os;
}

inline std::ostream& operator<<(std::ostream& os, const glm::fvec3& v) {
  os << utils::format("[%.3f, %.3f, %.3f]", v[0], v[1], v[2]);
  return os;
}

} // namespace glm
