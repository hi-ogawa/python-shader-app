//
// Cube map generator (for usage, see shaders/images/hdrihaven/README.md)
//
// About the coordinate system, see e.g.
// - https://www.khronos.org/opengl/wiki/Cubemap_Texture
// - https://www.khronos.org/registry/OpenGL/extensions/ARB/ARB_texture_cube_map.txt
// - https://github.com/OpenImageIO/oiio/blob/master/src/libtexture/environment.cpp
//

/*
%%config-start%%
plugins:
  # [ Quad to generate fragment ]
  - type: rasterscript
    params:
      exec: from misc.mesh.src import data; RESULT = list(map(bytes, data.quad()))
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertexPosition
      fragment_shader: mainFragmentCubemapGenerator
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 2, 2 * 4)"

  # [ Environment texture ]
  - type: texture
    params:
      name: tex_environment
      file: %%ENV:INFILE:shaders/images/hdrihaven/carpentry_shop_02_2k.hdr%%
      mipmap: false
      wrap: repeat
      filter: linear
      y_flip: true
      index: 0

  # [ Uniform UI ]
  - type: uniform
    params:
      name: U_rotate3_x
      default: "RESULT = float(os.environ.get('ROTATE3_X') or 0.0)"
      min: -1
      max: 1
  - type: uniform
    params:
      name: U_rotate3_y
      default: "RESULT = float(os.environ.get('ROTATE3_Y') or 0.0)"
      min: -1
      max: 1
  - type: uniform
    params:
      name: U_exposure
      default: 2
      min: -8
      max: 8

samplers: []
programs: []

offscreen_option:
  fps: 60
  num_frames: 1
%%config-end%%
*/

//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/misc_v0.glsl"

//
// Programs
//

#ifdef COMPILE_mainVertexPosition
  layout (location = 0) in vec2 Vertex_position;
  void main() {
    gl_Position = vec4(Vertex_position, 1 - 1e-7, 1.0);
  }
#endif

#ifdef COMPILE_mainFragmentCubemapGenerator
  uniform vec3 iResolution;
  uniform sampler2D tex_environment;
  uniform float U_rotate3_x = 0.0;
  uniform float U_rotate3_y = 0.0;
  uniform float U_exposure = 2.0;
  uniform float U_tonemap1 = 1.0;
  uniform float U_tonemap2 = 4.0;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    vec2 frag_coord = gl_FragCoord.xy;  // in [0, N]^2  (or precisely [1/2, N - 1/2]^2)
    vec2 p = 2.0 * frag_coord / iResolution.xy - 1.0;  // in [-1, 1]^2
    vec3 ray_dir = normalize(vec3(p, -1.0));
    mat3 rotate = T_rotate3(2.0 * M_PI * vec3(U_rotate3_x, U_rotate3_y, 0.0));
    ray_dir = rotate * ray_dir;

    vec2 uv = T_texcoordLatLng(ray_dir);
    vec3 L = texture(tex_environment, uv, 0.0).xyz;
    vec3 color = Misc_tonemap(L, U_exposure, U_tonemap1, U_tonemap2);
    Fragment_color = vec4(color, 1.0);
  }
#endif
