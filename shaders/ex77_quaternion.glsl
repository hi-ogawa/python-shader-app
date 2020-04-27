//
// Double cover S^3 -> SO(3) (aka. (unit) quaternion as 3d rotation)
//

/*
%%config-start%%
plugins:
  # [ Variable ]
  - type: uniformlist
    params:
      name: ['U_x', 'U_y', 'U_z', 'U_w', 'U_so3']
      default: [0.0, 0.0, 0.0, 1.0, 0.0]
      min: [-1, -1, -1, -1, 0]
      max: [+1, +1, +1, +1, 2]

  # [ Geometry : box ]
  - type: rasterscript
    params:
      exec: |
        from misc.mesh.src import data, utils
        p_vs, faces = data.cube()
        p_vs *= 0.5  # in [-0.5, 0.5]^3
        RESULT = list(map(bytes, utils.finalize(p_vs, faces, smooth=False)))
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertexBox
      fragment_shader: mainFragmentDefault
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 3) * 4)"
        Vertex_normal:   "(gl.GL_FLOAT, 3 * 4, 3, (3 + 3) * 4)"

  # [ Geometry : box frame ]
  - type: rasterscript
    params:
      exec: |
        from misc.mesh.src import data, utils
        import numpy as np; Np = np.array
        vs1 = Np([
          [0, 0, 0], [1, 0, 0],
          [0, 0, 0], [0, 1, 0],
          [0, 0, 0], [0, 0, 1],
        ], np.float32)
        vs2 = Np([
          [1, 0, 0, 1], [1, 0, 0, 1],
          [0, 1, 0, 1], [0, 1, 0, 1],
          [0, 0, 1, 1], [0, 0, 1, 1],
        ], np.float32)
        vs1 *= 0.8
        verts = utils.soa_to_aos(vs1, vs2)
        indices = np.arange(2 * len(verts), dtype=np.uint32)
        RESULT = list(map(bytes, [verts, indices]))
      primitive: GL_LINES
      vertex_shader: mainVertexBoxFrame
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"

  # [ Coordinate grid ]
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RESULT = ex01.make_coordinate_grids(axes=[0, 1, 2], grids=[1])
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertexColor
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"

  # [ UI state management ]
  - type: ssbo
    params: { binding: 0, type: size, size: 1024 }
  - type: raster
    params: { primitive: GL_POINTS, count: 1, vertex_shader: mainVertexUI, fragment_shader: mainFragmentDiscard }

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
#include "utils/misc_v0.glsl"

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(2.0, 1.5, 4.0) * 1.0;
const vec3  kLookatP = OZN.yyy;

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

uniform float U_x = 0.0;
uniform float U_y = 0.0;
uniform float U_z = 0.0;
uniform float U_w = 1.0;
uniform float U_so3 = 0.0;


//
// Programs
//

vec3 rotate(vec3 v) {
  vec4 q = normalize(vec4(U_x, U_y, U_z, U_w));
  mat3 A = q_to_so3(q);
  return (U_so3 < 1.0) ? q_apply(q, v) : A * v;
}

#ifdef COMPILE_mainVertexBox
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  out vec3 Interp_normal;
  out vec3 Interp_position;
  out float Interp_alpha;
  out vec4 Interp_color;

  void main() {
    vec3 p = Vertex_position;
    vec3 n = Vertex_normal;
    p = rotate(p);
    n = rotate(n);

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_position = p;
    Interp_normal = n;
    Interp_color = vec4(OZN.xxx, 1.0);
  }
#endif

#ifdef COMPILE_mainVertexBoxFrame
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec4 Vertex_color;
  out vec4 Interp_color;

  void main() {
    vec3 p = Vertex_position;
    p = rotate(p);

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_color = Vertex_color;
  }
#endif

#ifdef COMPILE_mainFragmentDefault
  in vec3 Interp_normal;
  in vec3 Interp_position;
  in float Interp_alpha;
  in vec4 Interp_color;
  layout (location = 0) out vec4 Fragment_color;

  vec3 Li(vec3 p, vec3 n, vec3 camera_p, vec3 surface_color) {
    const vec3 kRadienceEnv = vec3(0.15);
    const vec3 kRadiance = vec3(0.6) * M_PI;

    vec3 light_p = camera_p;  // Directional light from camera_p
    vec3 wo = normalize(camera_p - p);
    vec3 wi = normalize(light_p - p);
    vec3 wh = normalize(wo + wi);
    vec3 brdf = Brdf_default(wo, wi, wh, n, surface_color, 0.1);
    vec3 L = vec3(0.0);
    L += brdf * kRadiance * clamp0(dot(n, wi));
    L += surface_color * kRadienceEnv;
    return L;
  }

  void main() {
    vec3 p = Interp_position;
    vec3 n = normalize(Interp_normal);
    vec3 camera_p = vec3(Ssbo_camera_xform[3]);
    vec3 surface_color = Interp_color.xyz;
    vec3 color = Li(p, n, camera_p, surface_color);
    color = pow(color, vec3(1 / 2.2));
    Fragment_color = vec4(color, Interp_color.w);
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
