//
// CubemapPlugin test
//

/*
%%config-start%%
plugins:
  # [ UI state storage ]
  - type: ssbo
    params:
      binding: 0
      type: size
      size: 1024

  # [ Coordinate geometry ]
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RESULT = ex01.make_coordinate_grids(axes=[0, 1, 2], grids=[1], bound=1)
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertexColor
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"

  # [ Quad to shade environment ]
  - type: rasterscript
    params:
      exec: from misc.mesh.src import data; RESULT = list(map(bytes, data.quad()))
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertexEnvironment
      fragment_shader: mainFragmentEnvironment
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 2, 2 * 4)"

  # [ UI state management ]
  - type: raster
    params:
      primitive: GL_POINTS
      count: 1
      vertex_shader: mainVertexUI
      fragment_shader: mainFragmentDiscard

  # [ Environment texture ]
  - type: texture
    params:
      name: tex_environment
      file: shaders/images/hdrihaven/aft_lounge_2k.hdr
      #file: shaders/images/hdrihaven/carpentry_shop_02_2k.hdr
      mipmap: true
      wrap: repeat
      filter: linear
      y_flip: true
      index: 0

  # [ Environment texture ]
  - type: cubemap
    params:
      name: tex_environment_cube
      files:
        - shaders/images/hdrihaven/aft_lounge_2k.hdr.px.hdr
        - shaders/images/hdrihaven/aft_lounge_2k.hdr.py.hdr
        - shaders/images/hdrihaven/aft_lounge_2k.hdr.pz.hdr
        - shaders/images/hdrihaven/aft_lounge_2k.hdr.nx.hdr
        - shaders/images/hdrihaven/aft_lounge_2k.hdr.ny.hdr
        - shaders/images/hdrihaven/aft_lounge_2k.hdr.nz.hdr
        #- shaders/images/hdrihaven/carpentry_shop_02_cubemap_px.png
        #- shaders/images/hdrihaven/carpentry_shop_02_cubemap_py.png
        #- shaders/images/hdrihaven/carpentry_shop_02_cubemap_pz.png
        #- shaders/images/hdrihaven/carpentry_shop_02_cubemap_nx.png
        #- shaders/images/hdrihaven/carpentry_shop_02_cubemap_ny.png
        #- shaders/images/hdrihaven/carpentry_shop_02_cubemap_nz.png
      mipmap: true
      filter: linear
      index: 1

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
#include "utils/misc_v0.glsl"

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(0.5, 0.5, 4.0) * 1.5;
const vec3  kLookatP = vec3(0.0);

const bool kUseCubemap = true;

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

#ifdef COMPILE_mainVertexEnvironment
  layout (location = 0) in vec2 Vertex_position;
  void main() {
    gl_Position = vec4(Vertex_position, 1 - 1e-7, 1.0);
  }
#endif

#ifdef COMPILE_mainFragmentEnvironment
  uniform vec3 iResolution;
  uniform sampler2D tex_environment;
  uniform samplerCube tex_environment_cube;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    vec2 frag_coord = gl_FragCoord.xy;
    mat3 ray_xform = mat3(Ssbo_camera_xform) * mat3(OZN.xyy, OZN.yxy, OZN.yyz) * T_invView(kYfov, iResolution.xy);
    vec3 ray_dir = normalize(ray_xform * vec3(frag_coord, 1.0));
    if (kUseCubemap) {
      // flip to left-handed frame
      vec3 cube_ray_dir = vec3(1.0, 1.0, -1.0) * ray_dir;
      vec3 L = texture(tex_environment_cube, cube_ray_dir).xyz;
      vec3 color = encodeGamma(L);
      Fragment_color = vec4(color, 1.0);
      return;
    }
    vec2 uv = T_texcoordLatLng(ray_dir);
    vec3 L = texture(tex_environment, uv, 0.0).xyz;
    vec3 color = encodeGamma(L);
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

    vec4 color = Vertex_color;
    vec3 color_pre_alpha = color.xyz * Vertex_color.w;
    Interp_color = vec4(color_pre_alpha, 1.0);
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
