//
// RasterscriptPlugin test
//
// - [x] RasterScript plugin
// - [x] Coordinate grid
// - [x] Shading mode
//   - [x] normal          (mainVertexNormal)
//   - [x] simple lighting (mainVertexShading, mainFragmentShading)
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: size
      size: 1024
  - type: rasterscript
    params:
      # [ Geometry test (Regular polyhedra, subdivision, smooth normal)]
      #exec: |
      #  import misc.mesh.src.ex00 as ex00
      #  RELOAD_REC(ex00)
      #  # RESULT = ex00.example('cube', num_subdiv=1, smooth=False)
      #  # RESULT = ex00.example('cube', num_subdiv=2, smooth=False)
      #  RESULT = ex00.example('hedron20', num_subdiv=2, smooth=True)

      # [ Loader test ]
      exec: |
        import numpy as np
        from misc.mesh.src import utils, loader_ply, loader_obj, loader_gltf
        # [ ply ascii format ]
        p_vs, faces = loader_ply.load('misc/bvh/data/bunny/reconstruction/bun_zipper_res2.ply')
        # p_vs, faces = loader_ply.load('misc/bvh/data/dragon_recon/dragon_vrip_res2.ply')

        # [ ply binary format ]
        # p_vs, faces = loader_ply.load('misc/bvh/data/Armadillo.ply')

        # [ obj format ]
        # p_vs, faces = loader_obj.load('misc/bvh/data/spider.obj')

        p_vs = utils.normalize_positions(p_vs)
        verts, faces = utils.finalize(p_vs, faces, smooth=False)

        # [ gltf format ]
        verts_dict, faces = loader_gltf.load(
            'misc/bvh/data/gltf/DamagedHelmet/DamagedHelmet.gltf',
            'misc/bvh/data/gltf/DamagedHelmet/DamagedHelmet.bin')
        p_vs, n_vs = verts_dict['POSITION'], verts_dict['NORMAL']
        p_vs = utils.normalize_positions(p_vs)
        rotate = np.array([[1, 0, 0], [0, 0, 1], [0,-1, 0]], np.float32)
        p_vs = p_vs @ rotate
        n_vs = n_vs @ rotate
        verts = utils.soa_to_aos(p_vs, n_vs)

        RESULT = bytes(verts), bytes(faces)
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]

      # [ Simple lighting ]
      vertex_shader: mainVertexShading
      fragment_shader: mainFragmentShading

      # [ Normal shading mode ]
      # vertex_shader: mainVertexNormal
      # fragment_shader: mainFragmentColor

      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 3) * 4)"
        Vertex_normal:   "(gl.GL_FLOAT, 3 * 4, 3, (3 + 3) * 4)"

  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RELOAD_REC(ex01)
        RESULT = ex01.make_coordinate_grids()
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertexColor
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"
  - type: raster
    params:
      primitive: GL_POINTS
      count: 1
      vertex_shader: mainVertexUI
      fragment_shader: mainFragmentDiscard

samplers: []
programs: []

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

//
// SSBO definition
//

// Global state for interactive view
layout (std140, binding = 0) buffer Ssbo0 {
  bool Ssbo_mouse_down;
  vec2 Ssbo_mouse_down_p;
  vec2 Ssbo_mouse_click_p;
  mat4 Ssbo_camera_xform;
  vec3 Ssbo_lookat_p;
};


//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/ui_v0.glsl"
#include "utils/brdf_v0.glsl"

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(2.0, 1.5, 4.0);
const vec3  kLookatP = vec3(0.0);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

#ifdef COMPILE_mainVertexNormal
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  out vec4 Interp_color;

  void main() {
    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(Vertex_position, 1.0);
    Interp_color = vec4(0.5 + 0.5 * normalize(Vertex_normal), 1.0);
  }
#endif

#ifdef COMPILE_mainVertexShading
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  out vec4 Interp_color;
  out vec3 Interp_normal;   // TODO: do they interpolated in vec3(gl_Position) ??
  out vec3 Interp_position;

  void main() {
    Interp_position = Vertex_position;
    Interp_normal = Vertex_normal;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(Vertex_position, 1.0);
  }
#endif

#ifdef COMPILE_mainFragmentShading
  in vec4 Interp_color;
  in vec3 Interp_normal;
  in vec3 Interp_position;

  vec3 Li(vec3 p, vec3 n, vec3 camera_p) {
    const vec3 kAlbedo = vec3(0.8);
    const vec3 kRadienceEnv = vec3(0.15);
    const vec3 kRadiance = (1.0 - kRadienceEnv) * M_PI;

    vec3 light_p = camera_p;  // Directional light from camera_p
    vec3 wo = normalize(camera_p - p);
    vec3 wi = normalize(light_p - p);
    vec3 wh = normalize(wo + wi);
    vec3 brdf = Brdf_default(wo, wi, wh, n, kAlbedo, 0.1);
    vec3 L = vec3(0.0);
    L += brdf * kRadiance * clamp0(dot(n, wi));
    L += kAlbedo * kRadienceEnv;
    return L;
  }

  layout (location = 0) out vec4 Fragment_color;
  void main() {
    vec3 p = Interp_position;
    vec3 n = normalize(Interp_normal);
    vec3 camera_p = vec3(Ssbo_camera_xform[3]);
    vec3 color = Li(p, n, camera_p);
    color = pow(color, vec3(1 / 2.2));
    Fragment_color = vec4(color, 1.0);
  }
#endif


#ifdef COMPILE_mainVertexColor
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec4 Vertex_color;
  out vec4 Interp_color;

  void main() {
    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(Vertex_position, 1.0);
    Interp_color = Vertex_color;
  }
#endif

#ifdef COMPILE_mainFragmentColor
  in vec4 Interp_color;
  layout (location = 0) out vec4 Fragment_color;
  void main() {
    Fragment_color = Interp_color;
  }
#endif

#ifdef COMPILE_mainVertexUI
  uniform vec3 iResolution;
  uniform vec4 iMouse;
  uniform uint iKeyModifiers;

  void main() {
    bool interacted = UI_handleCameraInteraction(
        iResolution.xy, iMouse, iKeyModifiers,
        kCameraP, kLookatP,
        Ssbo_mouse_down, Ssbo_mouse_down_p, Ssbo_mouse_click_p,
        Ssbo_camera_xform, Ssbo_lookat_p);
  }
#endif

#ifdef COMPILE_mainFragmentDiscard
  layout (location = 0) out vec4 Fragment_color;
  void main() {
    discard;
  }
#endif
