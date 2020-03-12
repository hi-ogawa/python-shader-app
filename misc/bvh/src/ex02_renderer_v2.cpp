#include <memory>

#include "utils/ply.hpp"
#include "utils/bvh.hpp"
#include "utils/misc.hpp"
#include "utils/renderer_v2.hpp"


using std::string, std::vector, std::make_shared;
using namespace utils;


struct MyCamera : Camera {
  fvec3 camera_loc = {1, 1, 1};
  fvec3 lookat_loc = {0, 0, 0};
  fvec3 up_vec = {0, 1, 0};
  float yfov = 39.0f * M_PI / 180.0f;
  fmat3 ray_xform;

  virtual void onInitialize() {
    fmat3 inv_view_xform = xformInvView(yfov, (float)w, (float)h);
    fmat4 camera_xform = xformLookAt(camera_loc, lookat_loc, up_vec);
    ray_xform = fmat3{camera_xform} *
                fmat3{{1, 0, 0}, {0, 1, 0}, {0, 0, -1}} *
                inv_view_xform;
  }

  virtual Ray generateRay(int x, int y) {
    fvec2 frag_coord = fvec2{x, h - y - 1} + 0.5f;
    fvec3 ray_dir = ray_xform * fvec3{frag_coord, 1};
    return Ray{camera_loc, ray_dir, 1e30};
  }
};


struct MyScene : Scene {
  vector<fvec3> vertices;
  vector<uvec3> indices;
  Bvh bvh;

  MyScene(const string& filename) {
    loadPly(filename, vertices, indices);
    bvh = Bvh::create(vertices, indices, 2);
  }

  virtual bool intersect(const Ray& ray, /*out*/ Intersection* isect, /*in-opt*/ bool any_hit = false) {
    float hit_t;
    uint32_t hit_primitive;
    bool hit = bvh.rayIntersect(ray.o, ray.d, ray.tmax, /*out*/ hit_t, hit_primitive, /*in-opt*/ any_hit);
    if (!hit)
      return false;

    Triangle tri = getTriangle(vertices, indices, hit_primitive);
    isect->n = tri.normal();
    isect->p = ray.o + hit_t * ray.d;
    return true;
  };
};


struct HitIntegrator : Integrator {
  HitIntegrator(Yeml& y) {}

  virtual fvec3 Li(const Ray& ray, Scene& scene) {
    Intersection isect;
    bool hit = scene.intersect(ray, &isect);
    return fvec3{(float)hit};
  }
};
REGISTER_CLASS(HitIntegrator)

struct NormalIntegrator : Integrator {
  NormalIntegrator() {}
  NormalIntegrator(Yeml& y) {}

  virtual fvec3 Li(const Ray& ray, Scene& scene) {
    Intersection isect;
    bool hit = scene.intersect(ray, &isect);
    return hit ? isect.n * 0.5f + 0.5f : fvec3{0.5};
  }
};
REGISTER_CLASS(NormalIntegrator)

struct AmbientOcclusionIntegrator : Integrator {
  int num_samples;
  fvec3 background;
  float max_distance;
  float env_radiance;
  Rng rng;
  static constexpr float kRayTmin = 0.001;

  AmbientOcclusionIntegrator(Yeml& y) {
    num_samples = std::stoi(y.ds("num_samples").value_or("8"));
    background = sto<fvec3>(y.ds("background").value_or("0 0 0"));
    max_distance = std::stof(y.ds("max_distance").value_or("1e30"));
    env_radiance = std::stof(y.ds("env_radiance").value_or("1"));
  }

  virtual fvec3 Li(const Ray& ray, Scene& scene) {
    using glm::dot;

    Intersection isect;
    bool hit = scene.intersect(ray, &isect);
    if (!hit)
      return background;

    fvec3 L{0, 0, 0};
    Intersection isect_2nd;
    Ray ray_2nd = { .tmax = max_distance };
    for (auto i = 0; i < num_samples; i++) {
      fvec3 wi;
      float pdf;
      sample_HemisphereCosine(rng.uniform2(), wi, pdf);
      ray_2nd.d = xformZframe(isect.n) * wi;
      ray_2nd.o = isect.p + kRayTmin * ray_2nd.d;
      if (!scene.intersect(ray_2nd, &isect_2nd, /*any_hit*/ true))
        L += (env_radiance / M_PI) * dot(wi, isect.n) / pdf;
    }
    return L / (float)(num_samples);
  }
};
REGISTER_CLASS(AmbientOcclusionIntegrator)


struct MyRenderer : Renderer {
  Yeml y;
  vector<fvec3> result;

  MyRenderer(const Yeml& in_y) : y{in_y} {
    updateScene(y["scene"]);
    updateCamera(y["camera"]);
    updateIntegrator(y["integrator"]);
  }

  void update(Yeml& new_y) {
    if (new_y["scene"]["params"]("file") != y["scene"]["params"]("file")) {
      updateScene(new_y["scene"]);
    }
    updateCamera(new_y["camera"]);
    updateIntegrator(new_y["integrator"]);
    y.data = new_y.data;
  }

  void updateCamera(Yeml& y) {
    Yeml& yp = y["params"];
    auto c = new MyCamera;
    camera.reset(c);
    c->w = std::stoi(yp("w"));
    c->h = std::stoi(yp("h"));
    c->camera_loc = sto<fvec3>(yp("camera_loc"));
    if (yp("lookat_scene_center") == "1") {
      c->lookat_loc = dynamic_cast<MyScene*>(scene.get())->bvh.nodes[0].bbox.center();
    } else {
      c->lookat_loc = sto<fvec3>(yp("lookat_loc"));
    }
  }

  void updateScene(Yeml& y) {
    Yeml& yp = y["params"];
    scene.reset(new MyScene{yp("file")});
  }

  void updateIntegrator(Yeml& y) {
    Yeml& yp = y["params"];
    auto& reg = ClassRegistry::data;
    auto ptr = ClassRegistry::data.at(y("type"))(yp);
    integrator.reset(reinterpret_cast<Integrator*>(ptr));
  }

  void run() {
    result = render();

    // Convert to rgb bytes
    vector<u8vec3> result_bytes = mapVector<u8vec3, fvec3>(result,
        [](fvec3 v){ return u8vec3{glm::clamp(v * 256.0f, fvec3(0), fvec3(255))}; });

    std::ofstream ostr(y["output"]["params"]("file"));
    ostr << PPMWriter{camera->w, camera->h, result_bytes.data()};
  }
};


void render(const string& infile, const string& outfile, int w, int h) {
  print("[render] Loading %s\n", infile);
  auto scene = make_shared<MyScene>(infile);

  auto camera = make_shared<MyCamera>();
  camera->w = w;
  camera->h = h;
  camera->camera_loc = fvec3{1, 1, 1} * 0.2f;
  camera->lookat_loc = scene->bvh.nodes[0].bbox.center();

  print("[render] Rendering ...\n");
  Renderer renderer{
      camera,
      scene,
      make_shared<NormalIntegrator>()};
  vector<fvec3> result = renderer.render();

  // Convert to rgb bytes
  vector<u8vec3> result_bytes = mapVector<u8vec3, fvec3>(result,
      [](fvec3 v){ return u8vec3{glm::clamp(v * 256.0f, fvec3(0), fvec3(255))}; });

  print("[render] Writing result to %s\n", outfile);
  std::ofstream ofs(outfile);
  ofs << PPMWriter{camera->w, camera->h, result_bytes.data()};
}


int main(int argc, const char** argv) {
  Cli cli{argc, argv};
  int w = cli.getArg<int>("-w").value_or(300);
  int h = cli.getArg<int>("-h").value_or(300);
  auto infile  = cli.getArg<string>("--infile");
  auto outfile = cli.getArg<string>("--outfile");
  auto yaml = cli.getArg<string>("--yaml");

  // Yaml config mode
  if (yaml) {
    MyRenderer renderer{Yeml::parseFile(*yaml)};
    renderer.run();
    return 0;
  }

  // Previous mode
  if (!(infile && outfile)) {
    print(cli.help());
    return 1;
  }
  render(*infile, *outfile, w, h);
  return 0;
}
