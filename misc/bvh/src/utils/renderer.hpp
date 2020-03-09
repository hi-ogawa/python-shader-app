#pragma once

#include <glm/glm.hpp>

#include "format.hpp"
#include "geometry.hpp"
#include "misc.hpp"


namespace utils {

using RayIntersect_t = std::function<bool(
    const fvec3& ray_orig, const fvec3& ray_dir, float ray_tmax,
    /*out*/ float& hit_t, uint32_t& hit_primitive, /*in*/ bool any_hit)>;

struct RenderResult {
  vector2<uint8_t> hit; // avoid vector<bool>
  vector2<uint32_t> primitive;
  vector2<float> t;

  void resize(size_t h, size_t w) {
    hit.resize(h, w);
    primitive.resize(h, w);
    t.resize(h, w);
  }
};

struct Renderer {
  static inline RenderResult render(
      fvec3 eye_loc, fvec3 lookat_loc, fvec3 up_vec, float yfov,
      int w, int h, const RayIntersect_t& rayIntersect) {
    using glm::fmat3, glm::fmat4, glm::fvec2;
    fmat3 inv_view_xform = xformInvView(yfov, (float)w, (float)h);
    fmat4 camera_xform = xformLookAt(eye_loc, lookat_loc, up_vec);
    fmat3 ray_xform = fmat3{camera_xform} *
                      fmat3{{1, 0, 0}, {0, 1, 0}, {0, 0, -1}} *
                      inv_view_xform;
    RenderResult result;
    result.resize(h, w);
    for (auto y = 0; y < h; y++) {
      for (auto x = 0; x < w; x++) {
        fvec2 frag_coord = fvec2{x, h - y - 1} + 0.5f;
        fvec3 ray_dir = ray_xform * fvec3{frag_coord, 1};
        float hit_t;
        uint32_t hit_primitive;
        bool hit = rayIntersect(eye_loc, ray_dir, 1e30, /*out*/ hit_t, hit_primitive, false);
        result.hit(y, x) = (uint8_t)hit;
        result.primitive(y, x) = hit_primitive;
        result.t(y, x) = hit_t;
      }
    }
    return result;
  }
};


} // namespace utils
