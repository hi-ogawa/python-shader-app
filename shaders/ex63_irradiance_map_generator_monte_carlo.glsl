//
// Irradiance map generator (Monte Carlo)
//
// Usage:
//   NUM_SAMPLES=1024 H=256 INFILE=shaders/images/hdrihaven/fireplace_1k.hdr python -m src.app shaders/ex63_irradiance_map_generator_monte_carlo.glsl --offscreen /dev/zero
//

/*
%%config-start%%
plugins:
  # [ vec4 buffer ]
  - type: ssbo
    params:
      binding: 0
      type: size
      size: "4 * 4 * %%ENV:H:512%% ** 2 * 2"  # float * 4 * h * (h * 2)
      on_cleanup: |
        import os
        import numpy as np
        import misc.hdr.src.main as hdr
        w = %%ENV:H:512%%
        rgb = np.frombuffer(DATA, np.float32).reshape((w, w * 2, 4))[..., :3]
        infile = "%%ENV:INFILE:%%"
        if len(infile) != 0:
          hdr.write_file(infile + '.irr-montecarlo.hdr', rgb)

  # [ Environment texture ]
  - type: texture
    params:
      name: tex_environment
      file: %%ENV:INFILE:shaders/images/hdrihaven/fireplace_1k.hdr%%
      mipmap: false
      wrap: repeat
      filter: linear
      y_flip: true
      index: 0

  # [ Quad ]
  - type: rasterscript
    params:
      exec: from misc.mesh.src import data; RESULT = list(map(bytes, data.quad()))
      primitive: GL_TRIANGLES
      capabilities: []
      vertex_shader: mainVertex
      fragment_shader: mainFragment
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 2, 2 * 4)"

  # [ Variable for display ]
  - type: uniform
    params:
      name: U_exposure
      default: 0
      min: -4
      max: 4

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
    global_size: "[%%ENV:H:512%% * 2, %%ENV:H:512%%, 1]"
    samplers: []

offscreen_option:
  fps: 60
  num_frames: %%ENV:NUM_SAMPLES:1%%
%%config-end%%
*/

// ssbo definition
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

//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/misc_v0.glsl"
#include "utils/hash_v0.glsl"
#include "utils/sampling_v0.glsl"
#include "utils/ui_v0.glsl"

//
// Parameters
//

const ivec3 kSize = ivec3(%%ENV:H:512%% * 2, %%ENV:H:512%%, 1);
const float kDeltaTheta = M_PI / kSize.y;
const float kDeltaPhi = 2.0 * M_PI / kSize.x;
const int kNumSamplesPerFrame = 16;

int toDataIndex(ivec3 p, ivec3 size) {
  return size.y * size.x * p.z + size.x * p.y + p.x;
}


//
// Programs
//

#ifdef COMPILE_mainCompute
  uniform sampler2D tex_environment;

  vec3 Li(vec3 ray_dir) {
    vec2 uv = T_texcoordLatLng(ray_dir);
    return textureLod(tex_environment, uv, 0.0).xyz;
  }

  vec3 irradianceMonteCarlo(vec3 n) {
    vec3 I = vec3(0.0);
    for (int i = 0; i < kNumSamplesPerFrame; i++) {
      // Monte carlo evaluation of \int_{w} Li(w) (n.w)

      // [Halton sequence]
      vec2 u = Misc_halton2D(iFrame + 1);
      u = mod(u + hash32(n) * 0.01, 1.0); // with slight pixel-wise random offset

      // (n.w) distribution
      vec3 p, wi;
      float pdf;
      Sampling_hemisphereCosine(u, /*out*/ p, pdf);

      // [ or use uniform distribution]
      // Sampling_hemisphereUniform(u, /*out*/ p, pdf);

      I += Li(T_zframe(n) * p) * p.z / pdf;
    }
    I /= float(kNumSamplesPerFrame);
    return I;
  }

  vec3 irradianceFixedCount(vec3 n) {
    vec3 I = vec3(0.0);
    return I;
  }

  vec3 renderPixel(vec3 p) {
    float theta = kDeltaTheta * (float(p.y) + 0.5);
    float phi = kDeltaPhi * (float(p.x) + 0.5);
    vec3 n = T_sphericalToCartesian(vec3(1.0, theta, phi));
    n = vec3(-n.y, n.z, n.x); // to OpenGL frame
    vec3 L = irradianceMonteCarlo(n);
    // [debug]
    // L = Li(n);
    return L;
  }

  void mainCompute(/*unused*/ uvec3 comp_coord, uvec3 comp_local_coord) {
    ivec3 p = ivec3(gl_GlobalInvocationID);
    if (!all(lessThan(p, kSize))) { return; }
    int idx = toDataIndex(p, kSize);

    vec3 L_now = renderPixel(p);
    vec3 L_prev = Ssbo_data[idx].xyz;
    vec3 L = mix(L_prev, L_now, 1.0 / float(iFrame + 1));
    Ssbo_data[idx] = vec4(L, 1.0);
  }
#endif


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
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    vec2 frag_coord = T_apply2(Ssbo_inv_view_xform, gl_FragCoord.xy);
    ivec3 p = ivec3(frag_coord.x, iResolution.y - frag_coord.y, 0.0);

    vec3 L = Ssbo_data[toDataIndex(p, kSize)].xyz;
    L *= pow(2.0, U_exposure);

    vec3 color = encodeGamma(L);
    if (!all(lessThan(p, kSize))) { color *= 0.0; }
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
