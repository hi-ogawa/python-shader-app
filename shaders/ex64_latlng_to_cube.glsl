//
// Lat-lng format to cubemap format
//

/*
%%config-start%%
plugins:
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

// ssbo definition
layout (std140, binding = 0) buffer Ssbo0 {
  vec4 Ssbo_data[];
};

//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/misc_v0.glsl"

//
// Programs
//

#ifdef COMPILE_mainCompute
  uniform sampler2D tex_environment;

  vec3 renderPixel(vec2 frag_coord, vec2 resolution, mat3 rotate, sampler2D tex) {
    vec2 p = 2.0 * frag_coord / resolution - 1.0;  // in [-1, 1]^2
    vec3 ray_dir = rotate * normalize(vec3(p, -1.0));
    vec2 uv = T_texcoordLatLng(ray_dir);
    vec3 L = texture(tex, uv).xyz;
    return L;
  }

  void mainCompute(uvec3 comp_coord, /*unused*/ uvec3 comp_local_coord) {
    ivec3 size = ivec3(gl_NumWorkGroups * gl_WorkGroupSize);
    ivec3 p = ivec3(comp_coord);
    int idx = size.y * size.x * p.z + size.x * p.y + p.x;
    if (!all(lessThan(p, size))) { return; }

    const vec2 kRot[6] = vec2[6](
        vec2(0.00, 0.00),
        vec2(0.00, 0.25),
        vec2(0.00, 0.50),
        vec2(0.00, 0.75),
        vec2(0.25, 0.00),
        vec2(0.75, 0.00));

    vec2 frag_coord = vec2(p.xy) + 0.5;
    mat3 rotate = T_rotate3(2.0 * M_PI * vec3(kRot[p.z], 0.0));
    vec3 L = renderPixel(frag_coord, size.xy, rotate, tex_environment);
    Ssbo_data[idx] = vec4(L, 1.0);
  }
#endif
