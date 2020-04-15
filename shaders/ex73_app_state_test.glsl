//
// APP state test (pass data from UniformlistPlugin to RasterscriptPlugin)
//


/*
%%config-start%%
plugins:
  # [ Variable ]
  - type: uniformlist
    params:
      name: ['U_f000', 'U_f100', 'U_f110', 'U_f010', 'U_f001', 'U_f101', 'U_f111', 'U_f011', 'U_threshold']
      default: [1.0, 0.0, 0.2, 1.0, 1.0, 1.0, 1.0, 0.2,   0.5]
      min: [0, 0, 0, 0, 0, 0, 0, 0,   0]
      max: [1, 1, 1, 1, 1, 1, 1, 1,   1]

  # [ Single marching cube ]
  - type: rasterscript
    params:
      exec: RESULT = [bytes(0), bytes(0)]
      exec_on_begin_draw: |
        from misc.mesh.src import utils as mesh_utils
        from misc.marching_cube.src import utils, table_all_faces, table_marching_cube
        f = [APP[f"U_f{name}"] for name in ['000', '100', '110', '010', '001', '101', '111', '011']]
        threshold = APP['U_threshold']
        # [ all faces ]
        #positions, faces = utils.marching_cube_single(f, threshold, table_all_faces.data)
        # [ marching cube faces ]
        positions, faces = utils.marching_cube_single(f, threshold, table_marching_cube.data)
        RESULT = list(map(bytes, mesh_utils.finalize(positions, faces, smooth=False)))
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertexShading
      fragment_shader: mainFragmentShading
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 3) * 4)"
        Vertex_normal:   "(gl.GL_FLOAT, 3 * 4, 3, (3 + 3) * 4)"

  # [ Coordinate grid ]
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RESULT = ex01.make_coordinate_grids(axes=[0, 1, 2], bound=4)
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertexColor
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"

  # [ UI ]
  - type: ssbo
    params:
      binding: 0
      type: size
      size: 1024
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
const vec3  kCameraP = vec3(2.0, 1.5, 4.0) * 1.0;
const vec3  kLookatP = vec3(0.5);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

#ifdef COMPILE_mainVertexShading
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  out vec3 Interp_normal;
  out vec3 Interp_position;

  void main() {
    Interp_position = Vertex_position;
    Interp_normal = Vertex_normal;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(Vertex_position, 1.0);
  }
#endif

#ifdef COMPILE_mainFragmentShading
  in vec3 Interp_normal;
  in vec3 Interp_position;

  vec3 Li(vec3 p, vec3 n, vec3 camera_p, vec3 color) {
    const vec3 kRadiance = vec3(1.0) * M_PI;

    vec3 light_p = camera_p;  // Directional light from camera_p
    vec3 wo = normalize(camera_p - p);
    vec3 wi = normalize(light_p - p);
    vec3 wh = normalize(wo + wi);
    vec3 brdf = Brdf_default(wo, wi, wh, n, color, 0.1);

    vec3 L = vec3(0.0);
    L += brdf * kRadiance * clamp0(dot(n, wi));
    return L;
  }

  layout (location = 0) out vec4 Fragment_color;
  void main() {
    vec3 p = Interp_position;
    vec3 camera_p = vec3(Ssbo_camera_xform[3]);
    vec3 n = normalize(Interp_normal);
    float orientation = sign(dot(n, camera_p - p));
    n *= orientation;
    vec3 surface_color = mix(vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), step(0.0, orientation));
    vec3 color = Li(p, n, camera_p, surface_color);
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
