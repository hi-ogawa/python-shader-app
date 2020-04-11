//
// Microface specular environment map generator
//

/*
Usage:
INFILE=shaders/images/hdrihaven/lythwood_lounge_2k.hdr NUM_FRAMES=1024 H=512 ROUGHNESS=0.2 python -m src.app --width 1 --height 1 shaders/ex68_microfacet_specular_environment_map_generator.glsl --offscreen /dev/zero
INFILE=shaders/images/hdrihaven/lythwood_lounge_2k.hdr NUM_FRAMES=1024 H=256 ROUGHNESS=0.4 python -m src.app --width 1 --height 1 shaders/ex68_microfacet_specular_environment_map_generator.glsl --offscreen /dev/zero
INFILE=shaders/images/hdrihaven/lythwood_lounge_2k.hdr NUM_FRAMES=1024 H=128 ROUGHNESS=0.6 python -m src.app --width 1 --height 1 shaders/ex68_microfacet_specular_environment_map_generator.glsl --offscreen /dev/zero
INFILE=shaders/images/hdrihaven/lythwood_lounge_2k.hdr NUM_FRAMES=1024 H=64  ROUGHNESS=0.8 python -m src.app --width 1 --height 1 shaders/ex68_microfacet_specular_environment_map_generator.glsl --offscreen /dev/zero
INFILE=shaders/images/hdrihaven/lythwood_lounge_2k.hdr NUM_FRAMES=1024 H=32  ROUGHNESS=1.0 python -m src.app --width 1 --height 1 shaders/ex68_microfacet_specular_environment_map_generator.glsl --offscreen /dev/zero
*/

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
        h = %%ENV:H:512%%
        rgb = np.frombuffer(DATA, np.float32).reshape((h, h * 2, 4))[..., :3]
        infile = "%%ENV:INFILE:%%"
        infix = "ex68-%%ENV:ROUGHNESS:0.2%%-%%ENV:H:512%%"
        if len(infile) != 0:
          hdr.write_file(f"{infile}.{infix}.hdr", rgb)

  # [ Environment texture ]
  - type: texture
    params:
      name: tex_environment
      file: %%ENV:INFILE:shaders/images/hdrihaven/lythwood_lounge_2k.hdr%%
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
      default: -2
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
  num_frames: %%ENV:NUM_FRAMES:1%%
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
#include "utils/brdf_v0.glsl"

//
// Parameters
//

const ivec3 kSize = ivec3(%%ENV:H:512%% * 2, %%ENV:H:512%%, 1);
const float kDeltaTheta = M_PI / kSize.y;
const float kDeltaPhi = 2.0 * M_PI / kSize.x;
const int kNumSamplesPerFrame = 8;
const float kRoughness = %%ENV:ROUGHNESS:0.2%%;


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

  vec3 integrate(vec3 n, float roughness) {
    vec3 L = vec3(0.0);

    // Setup brdf related parameters
    vec3 wo = n;
    float a = pow2(roughness);
    float a2 = pow2(a);

    for (int i = 0; i < kNumSamplesPerFrame; i++) {
      //
      // [ My formula ]
      //   int_wi D(wh) Li(wi) (n.wi)
      //   = int_wh D(wh) J(wh) Li(wi) (n.wi)   (change of var wi = refl(wo | wh))
      //
      //   for Monte Carlo evaluation, sample density is "rho(wh) = D(wh) n.wh"
      //

      //
      // [ Epic's formula ]
      //   int_wh D(wh) (wh.n) Li(wi) (n.wi)
      //
      // NOTE:
      //   - from sample density, it implicitly has "wh.n"
      //   - it skips jacobian of change of var
      //

      vec3 n_wh;
      float pdf;
      vec2 u = Misc_halton2D(kNumSamplesPerFrame * iFrame + i + 1);
      u = mod(u + hash32(n) * 0.01, vec2(1.0));  // with slight pixel-wise random offset
      Brdf_GGX_sampleCosineD(u, a, /*out*/ n_wh, pdf);

      vec3 wh = T_zframe(n) * n_wh;
      vec3 wi = 2.0 * dot(wh, wo) * wh - wo; // reflect
      float n_o_wh = dot(n, wh);
      float n_o_wo = dot(n, wo);
      float n_o_wi = dot(n, wi);
      float wh_o_wo = dot(wh, wo);
      float wh_o_wi = dot(wh, wi);

      vec3 Li_env = Li(wi);
      float D = Brdf_GGX_D(n_o_wh, a2);
      float J = 4.0 * wh_o_wo;

      // [ My formula ]
      // L += J * D * Li_env * clamp0(n_o_wi) / pdf;

      // [ Epic's formula ]
      L += D * n_o_wh * Li_env * clamp0(n_o_wi) / pdf;
    }
    L /= float(kNumSamplesPerFrame);
    return L;
  }

  vec3 renderPixel(vec3 p) {
    float theta = kDeltaTheta * (float(p.y) + 0.5);
    float phi = kDeltaPhi * (float(p.x) + 0.5);
    vec3 n = T_sphericalToCartesian(vec3(1.0, theta, phi));
    n = vec3(-n.y, n.z, n.x); // to OpenGL frame
    vec3 L = integrate(n, kRoughness);

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
    if (iFrame == 0) { L_prev = vec3(0.0); }
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
