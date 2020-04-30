//
// Tiling sphere (Mobius triangle (3, 3, 2), (4, 3, 2), (5, 3, 2))
//

/*
%%config-start%%
plugins:
  # [ Geometry ]
  - type: rasterscript
    params:
      exec: |
        from misc.mesh.src import data, utils
        import numpy as np

        def mobius(p_vs, faces, origin, to_sphere=True):
          p_vs = utils.normalize(p_vs)
          p_vs, faces, parity = utils.subdiv_mobius(p_vs, faces)
          parity = parity.reshape((-1, 1))
          for _ in range(3):
            p_vs, faces, parity = utils.subdiv_triforce(p_vs, faces, face_attrs=parity)
          if to_sphere:
            p_vs = utils.normalize(p_vs)
          p_vs += origin
          verts, faces = utils.finalize(p_vs, faces, smooth=True, face_attrs=parity)
          return verts, faces

        verts, faces = utils.concat(
            mobius(*data.hedron4(),  np.float32([-2.2, 0, 0])),
            mobius(*data.hedron8(),  np.float32([   0, 0, 0])),
            mobius(*data.hedron20(), np.float32([+2.2, 0, 0])),
            mobius(*data.hedron4(),  np.float32([-2.2, 2.5, 0]), to_sphere=False),
            mobius(*data.hedron8(),  np.float32([   0, 2.5, 0]), to_sphere=False),
            mobius(*data.hedron20(), np.float32([+2.2, 2.5, 0]), to_sphere=False))
        RESULT = bytes(verts), bytes(faces)

      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertex
      fragment_shader: mainFragmentShading
      vertex_attributes:
        VertexIn_position: "(gl.GL_FLOAT, 0 * 4, 3, 7 * 4)"
        VertexIn_normal:   "(gl.GL_FLOAT, 3 * 4, 3, 7 * 4)"
        VertexIn_parity: "(gl.GL_FLOAT, 6 * 4, 1, 7 * 4)"

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

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(0.0, 1.0, 3.0) * 3.0;
const vec3  kLookatP = vec3(0.0, 1.25, 0.0);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

#ifdef COMPILE_mainVertex
  uniform vec3 iResolution;
  layout (location = 0) in vec3 VertexIn_position;
  layout (location = 1) in vec3 VertexIn_normal;
  layout (location = 2) in float VertexIn_parity;
  out vec3 VertexOut_position;
  out vec3 VertexOut_normal;
  out vec4 VertexOut_color;

  void main() {
    vec3 p = VertexIn_position;
    vec3 n = VertexIn_normal;
    vec4 color = vec4(1.0);
    color.xyz = mix(vec3(1.0, 0.7, 0.0), vec3(0.0, 1.0, 0.7), step(0.0, VertexIn_parity));

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    VertexOut_position = p;
    VertexOut_normal = n;
    VertexOut_color = color;
  }
#endif

#ifdef COMPILE_mainFragmentShading
  in vec3 VertexOut_normal;
  in vec3 VertexOut_position;
  in vec4 VertexOut_color;
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
    vec3 p = VertexOut_position;
    vec3 n = normalize(VertexOut_normal);
    vec4 c = VertexOut_color;
    vec3 camera_p = vec3(Ssbo_camera_xform[3]);
    vec3 color = Li(p, n, camera_p, c.xyz);
    color = pow(color, vec3(1 / 2.2));
    Fragment_color = vec4(color, c.w);
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
