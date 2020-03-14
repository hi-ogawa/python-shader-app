#pragma once

#include <memory>

#include "format.hpp"
#include "geometry.hpp"


namespace utils {

//
// pbrt-like architecture (see ex02_renderer_v2.cpp for inherited use)
//

struct Intersection {
  fvec3 p;
  fvec3 n;
};

struct Ray {
  fvec3 o, d;
  float tmax = 1e30;
};

struct Scene {
  virtual bool intersect(const Ray& ray, /*out*/ Intersection* isect, /*opt-in*/ bool any_hit = false) {
    return false;
  };
};

struct Camera {
  int w, h;
  virtual void onInitialize() {}
  virtual Ray generateRay(int x, int y) {
    return Ray{};
  }
  virtual Ray generateRay_v2(float x, float y) {
    return Ray{};
  }
};

struct Integrator {
  virtual fvec3 Li(const Ray& ray, Scene& scene) {
    return fvec3{0.0, 1.0, 1.0};
  }
};

struct Renderer {
  std::shared_ptr<Camera> camera;
  std::shared_ptr<Scene> scene;
  std::shared_ptr<Integrator> integrator;

  vector<fvec3> render() {
    camera->onInitialize();
    int h = camera->h; int w = camera->w;
    vector<fvec3> result;
    result.resize(h * w);
    fvec3* p_result = result.data();
    for (auto y = 0; y < h; y++) {
      for (auto x = 0; x < w; x++) {
        Ray ray = camera->generateRay(x, y);
        *p_result = integrator->Li(ray, *scene);
        p_result++;
      }
    }
    return result;
  }
};


} // namespace utils
