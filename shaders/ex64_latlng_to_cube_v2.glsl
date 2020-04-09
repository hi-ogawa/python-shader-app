//
// Lat-lng format to cubemap format (with fragment shader for preview)
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

  # [ Buffer ]
  - type: ssbo
    params:
      binding: 0
      type: size
      size: "4 * 4 * 512 * 512 * 6"  # float * 4 * h * w * 6
      on_cleanup: |
        import os
        import numpy as np
        import misc.hdr.src.main as hdr
        rgb = np.frombuffer(DATA, np.float32).reshape((6, 512, 512, 4))[..., :3]
        rgb = np.flip(rgb, axis=1)
        out = os.environ.get('OUT')
        if out:
          for i, infix in enumerate(['pz', 'nx', 'nz', 'px', 'py', 'ny']):
            hdr.write_file(f"{out}.{infix}.hdr", rgb[i])

  # [ Environment texture ]
  - type: texture
    params:
      name: tex_environment
      file_exec: "RESULT = os.environ.get('INFILE') or 'shaders/images/hdrihaven/carpentry_shop_02_2k.hdr'"
      mipmap: false
      wrap: repeat
      filter: linear
      y_flip: true
      index: 0

  - type: uniform
    params:
      name: U_exposure
      default: 0
      min: -8
      max: 8

  - type: uniform
    params:
      name: U_index
      default: -1
      min: -2
      max: 5

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
programs:
  - name: mainCompute
    type: compute
    local_size: [32, 32, 1]
    global_size: [512, 512, 6]
    samplers: []

offscreen_option:
  fps: 60
  num_frames: 1
%%config-end%%
*/

// ssbo: cube map data buffer
layout (std140, binding = 0) buffer Ssbo0 {
  vec4 Ssbo_data[];
};

// ssbo: ui state
layout (std140, binding = 1) buffer Ssbo1 {
  bool Ssbo_mouse_down;
  vec2 Ssbo_mouse_down_p;
  vec2 Ssbo_mouse_click_p;
  mat3 Ssbo_inv_view_xform;
};

const ivec3 kSize = ivec3(512, 512, 6);

//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/misc_v0.glsl"
#include "utils/ui_v0.glsl"


int toDataIndex(ivec3 p, ivec3 size) {
  return size.y * size.x * p.z + size.x * p.y + p.x;
}

//
// Program: compute
//

#ifdef COMPILE_mainCompute
  uniform sampler2D tex_environment;

  vec3 renderPixel(vec2 frag_coord, vec2 resolution, mat3 rotate, sampler2D tex) {
    vec2 p = 2.0 * frag_coord / resolution - 1.0;  // in [-1, 1]^2
    vec3 ray_dir = rotate * normalize(vec3(p, -1.0));
    vec2 uv = T_texcoordLatLng(ray_dir);
    vec3 L = textureLod(tex, uv, 0.0).xyz;
    return L;
  }

  void mainCompute(uvec3 comp_coord, /*unused*/ uvec3 comp_local_coord) {
    ivec3 p = ivec3(comp_coord);
    if (!all(lessThan(p, kSize))) { return; }
    int idx = toDataIndex(p, kSize);

    const vec2 kRot[6] = vec2[6](
        vec2(0.00, 0.00),
        vec2(0.00, 0.25),
        vec2(0.00, 0.50),
        vec2(0.00, 0.75),
        vec2(0.25, 0.00),
        vec2(0.75, 0.00));

    vec2 frag_coord = vec2(p.xy) + 0.5;
    mat3 rotate = T_rotate3(2.0 * M_PI * vec3(kRot[p.z], 0.0));
    vec3 L = renderPixel(frag_coord, kSize.xy, rotate, tex_environment);
    Ssbo_data[idx] = vec4(L, 1.0);
  }
#endif


//
// Program: quad
//

#ifdef COMPILE_mainVertex
  layout (location = 0) in vec2 Vertex_position;
  void main() {
    gl_Position = vec4(Vertex_position, 1 - 1e-7, 1.0);
  }
#endif

#ifdef COMPILE_mainFragment
  uniform vec3 iResolution;
  uniform float U_exposure = 0.0;
  uniform float U_index = 0.0; // -2, -1, 0, 1, 2, 3, 4, 5
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    vec2 frag_coord = T_apply2(Ssbo_inv_view_xform, gl_FragCoord.xy);
    int mode = int(U_index);
    ivec3 p;

    // 0 -> pz
    // 1 -> nx
    // 2 -> nz
    // 3 -> px
    // 4 -> py
    // 5 -> ny
    if (mode >= 0) {
      p = ivec3(ivec2(frag_coord), int(U_index));
    }

    // cf. https://github.com/OpenImageIO/oiio/blob/master/src/libtexture/environment.cpp
    // px py pz
    // nx ny nz
    if (mode == -2) {
      vec2 q = frag_coord * 2.0 / iResolution.y; // in [0, ?] x [0, 2]
      p.xy = ivec2(fract(q) * kSize.xy);
      p.z = -1;
      if (all(equal(ivec2(q), ivec2(2, 1)))) { p.z = 0; }
      if (all(equal(ivec2(q), ivec2(0, 0)))) { p.z = 1; }
      if (all(equal(ivec2(q), ivec2(2, 0)))) { p.z = 2; }
      if (all(equal(ivec2(q), ivec2(0, 1)))) { p.z = 3; }
      if (all(equal(ivec2(q), ivec2(1, 1)))) { p.z = 4; }
      if (all(equal(ivec2(q), ivec2(1, 0)))) { p.z = 5; }
    }

    //    py
    // nx pz px nz
    //    ny
    if (mode == -1) {
      vec2 q = frag_coord * 3.0 / iResolution.y; // in [0, ?] x [0, 3]
      p.xy = ivec2(fract(q) * kSize.xy);
      p.z = -1;
      if (all(equal(ivec2(q), ivec2(1, 1)))) { p.z = 0; }
      if (all(equal(ivec2(q), ivec2(0, 1)))) { p.z = 1; }
      if (all(equal(ivec2(q), ivec2(3, 1)))) { p.z = 2; }
      if (all(equal(ivec2(q), ivec2(2, 1)))) { p.z = 3; }
      if (all(equal(ivec2(q), ivec2(1, 2)))) { p.z = 4; }
      if (all(equal(ivec2(q), ivec2(1, 0)))) { p.z = 5; }
    }

    int idx = toDataIndex(p, kSize);
    vec3 L = Ssbo_data[idx].xyz;
    L *= pow(2.0, U_exposure);
    vec3 color = encodeGamma(L);
    if (!all(lessThan(p, kSize))) {
      color *= 0.0;
    }
    Fragment_color = vec4(color, 1.0);
  }
#endif


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
