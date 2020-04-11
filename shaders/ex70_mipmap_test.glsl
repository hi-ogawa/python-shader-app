//
// Mipmap test
// - preview data generated via glGenerateMipmap
// - explicit mipmap data
//

/*
%%config-start%%
plugins:
  # [ Quad ]
  - type: rasterscript
    params:
      exec: from misc.mesh.src import data; RESULT = list(map(bytes, data.quad()))
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertex
      fragment_shader: mainFragment
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 2, 2 * 4)"

  # [ texture ]
  - type: texture
    params:
      name: tex
      #file: shaders/images/hdrihaven/lythwood_lounge_1k.hdr
      #file: shaders/images/generated/ex71.16.png
      file_mipmaps:
        - shaders/images/generated/ex71.16.png
        - shaders/images/generated/ex71.8.png
        - shaders/images/generated/ex71.4.png
      mipmap: true
      wrap: clamp
      filter: nearest
      y_flip: true
      index: 0

  # [ Uniform UI ]
  - type: uniform
    params:
      name: U_level
      default: 0
      min: 0
      max: 10

  # [ Image viewer interaction ]
  - type: ssbo
    params:
      binding: 1
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
  num_frames: 1
%%config-end%%
*/

// ssbo: ui state
layout (std140, binding = 1) buffer Ssbo1 {
  bool Ssbo_mouse_down;
  vec2 Ssbo_mouse_down_p;
  vec2 Ssbo_mouse_click_p;
  mat3 Ssbo_inv_view_xform;
};

//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/misc_v0.glsl"
#include "utils/ui_v0.glsl"


//
// Program: Quad
//

#ifdef COMPILE_mainVertex
  layout (location = 0) in vec2 Vertex_position;
  void main() {
    gl_Position = vec4(Vertex_position, 1 - 1e-7, 1.0);
  }
#endif

#ifdef COMPILE_mainFragment
  uniform vec3 iResolution;
  uniform sampler2D tex;
  uniform float U_level = 0.0;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    vec2 frag_coord = T_apply2(Ssbo_inv_view_xform, gl_FragCoord.xy);
    vec3 L = texelFetch(tex, ivec2(frag_coord), int(U_level)).xyz;
    vec3 color = encodeGamma(L);
    if (any(lessThan(frag_coord, vec2(0.0)))) {
      color = vec3(0.0);
    }
    Fragment_color = vec4(color, 1.0);
  }
#endif


//
// Program: UI
//

#ifdef COMPILE_mainVertexUI
  uniform vec3 iResolution;
  uniform vec4 iMouse;
  uniform uint iKeyModifiers;
  uniform int iFrame;

  void main() {
    if (iFrame == 0) { Ssbo_inv_view_xform = mat3(1.0); }

    UI_interactInvViewXform(iResolution.xy, iMouse, iKeyModifiers,
        Ssbo_mouse_down, Ssbo_mouse_down_p, Ssbo_mouse_click_p, Ssbo_inv_view_xform);
  }
#endif

#ifdef COMPILE_mainFragmentDiscard
  layout (location = 0) out vec4 Fragment_color;
  void main() {
    discard;
  }
#endif
