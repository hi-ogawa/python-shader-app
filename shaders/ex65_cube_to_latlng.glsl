//
// Cube format to lat-lng format
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
      size: "4 * 4 * 2**10 * 2**11"  # float * 4 * h * w
      on_cleanup: |
        import os
        import numpy as np
        import misc.hdr.src.main as hdr
        rgb = np.frombuffer(DATA, np.float32).reshape((2**10, 2**11, 4))[..., :3]
        outfile = os.environ.get('OUTFILE')
        if outfile:
          hdr.write_file(outfile, rgb)

  # [ Environment texture ]
  - type: cubemap
    params:
      name: tex_environment_cube
      files:
        - shaders/images/hdrihaven/carpentry_shop_02_2k.hdr.px.hdr
        - shaders/images/hdrihaven/carpentry_shop_02_2k.hdr.py.hdr
        - shaders/images/hdrihaven/carpentry_shop_02_2k.hdr.pz.hdr
        - shaders/images/hdrihaven/carpentry_shop_02_2k.hdr.nx.hdr
        - shaders/images/hdrihaven/carpentry_shop_02_2k.hdr.ny.hdr
        - shaders/images/hdrihaven/carpentry_shop_02_2k.hdr.nz.hdr
        #- shaders/images/hdrihaven/aft_lounge_2k.hdr.px.hdr
        #- shaders/images/hdrihaven/aft_lounge_2k.hdr.py.hdr
        #- shaders/images/hdrihaven/aft_lounge_2k.hdr.pz.hdr
        #- shaders/images/hdrihaven/aft_lounge_2k.hdr.nx.hdr
        #- shaders/images/hdrihaven/aft_lounge_2k.hdr.ny.hdr
        #- shaders/images/hdrihaven/aft_lounge_2k.hdr.nz.hdr
        #- shaders/images/pauldebevec/galileo_cross.hdr.px.hdr
        #- shaders/images/pauldebevec/galileo_cross.hdr.py.hdr
        #- shaders/images/pauldebevec/galileo_cross.hdr.pz.hdr
        #- shaders/images/pauldebevec/galileo_cross.hdr.nx.hdr
        #- shaders/images/pauldebevec/galileo_cross.hdr.ny.hdr
        #- shaders/images/pauldebevec/galileo_cross.hdr.nz.hdr
      mipmap: false
      filter: linear
      index: 0

  # [ Variable for display ]
  - type: uniform
    params:
      name: U_exposure
      default: 0
      min: -8
      max: 8
  - type: uniform
    params:
      name: U_scale
      default: 0.25
      min: 0.1
      max: 2.0

samplers: []
programs:
  - name: mainCompute
    type: compute
    local_size: [32, 32, 1]
    global_size: [2048, 1024, 1]
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

const ivec3 kSize = ivec3(2048, 1024, 1);
const float kDeltaTheta = M_PI / kSize.y;
const float kDeltaPhi = 2.0 * M_PI / kSize.x;


int toDataIndex(ivec3 p, ivec3 size) {
  return size.y * size.x * p.z + size.x * p.y + p.x;
}

//
// Program: compute
//

#ifdef COMPILE_mainCompute
  uniform samplerCube tex_environment_cube;

  vec3 renderPixel(vec3 p, samplerCube tex) {
    float theta = kDeltaTheta * (float(p.y) + 0.5);
    float phi = kDeltaPhi * (float(p.x) + 0.5);
    vec3 d = T_sphericalToCartesian(vec3(1.0, theta, phi));
    vec3 ray_dir = vec3(-d.y, d.z, -d.x);
    vec3 L = textureLod(tex, ray_dir, 0.0).xyz;
    return L;
  }

  void mainCompute(/*unused*/ uvec3 comp_coord, uvec3 comp_local_coord) {
    ivec3 p = ivec3(gl_GlobalInvocationID);
    if (!all(lessThan(p, kSize))) { return; }

    vec3 L = renderPixel(p, tex_environment_cube);
    Ssbo_data[toDataIndex(p, kSize)] = vec4(L, 1.0);
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
  uniform samplerCube tex_environment_cube;
  uniform float U_exposure = 0.0;
  uniform float U_scale = 0.4;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    vec2 frag_coord = gl_FragCoord.xy;
    ivec3 p = ivec3(frag_coord.x, iResolution.y - frag_coord.y, 0.0);
    p.xy = ivec2(vec2(p.xy) / U_scale);

    vec3 L = Ssbo_data[toDataIndex(p, kSize)].xyz;
    L *= pow(2.0, U_exposure);

    vec3 color = encodeGamma(L);
    if (!all(lessThan(p, kSize))) { color *= 0.0; }
    Fragment_color = vec4(color, 1.0);
  }
#endif
