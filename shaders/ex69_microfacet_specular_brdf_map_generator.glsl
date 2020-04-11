//
// Microface specular brdf map generator
//
//   int_wi D Vis F (n.wi) = p F0 + q (1 - F0)
//     where
//       p = (int_wi D Vis (n.wi))
//       q = (int_wi D Vis (1 - n.wo)^5 (n.wi))
//
// Usage:
//   OUTFILE=shaders/images/generated/ex69.hdr NUM_FRAMES=256 python -m src.app shaders/ex69_microfacet_specular_brdf_map_generator.glsl --offscreen /dev/zero
//

/*
%%config-start%%
plugins:
  # [ vec4 buffer ]
  - type: ssbo
    params:
      binding: 0
      type: size
      size: "4 * 4 * 256 * 256"  # float * 4 * h * w
      on_cleanup: |
        import os
        import numpy as np
        import misc.hdr.src.main as hdr
        h = 256
        rgb = np.frombuffer(DATA, np.float32).reshape((h, h, 4))[..., :3]
        outfile = "%%ENV:OUTFILE:%%"
        if len(outfile) != 0:
          hdr.write_file(outfile, rgb)

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
  #- type: uniform
  #  params:
  #    name: U_exposure
  #    default: 0
  #    min: -4
  #    max: 4

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
    global_size: [256, 256, 1]
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

const ivec3 kSize = ivec3(256, 256, 1);
const int kNumSamplesPerFrame = 8;


int toDataIndex(ivec3 p, ivec3 size) {
  return size.y * size.x * p.z + size.x * p.y + p.x;
}


//
// Programs
//

#ifdef COMPILE_mainCompute
  vec2 integrate(float n_o_wo, float roughness) {
    vec2 result = vec2(0.0);

    // Setup brdf related parameters
    vec3 n = vec3(0.0, 0.0, 1.0);
    vec3 wo = vec3(sqrt(1.0 - pow2(n_o_wo)), 0.0, n_o_wo);
    roughness = mix(0.05, 1.0, roughness); // a = 0 causes NAN
    float a = pow2(roughness);
    float a2 = pow2(a);

    for (int i = 0; i < kNumSamplesPerFrame; i++) {
      // Monte carlo evaluation of
      //   int_wi D Vis F (n.wi) = p F0 + q (1 - F0) = (p - q) F0 + q
      //     where
      //       p = (int_wi D Vis (n.wi))
      //       q = (int_wi D Vis (1 - n.wo)^5 (n.wi))
      // - sample density is "rho(wh) = D(wh) n.wh"
      // - change of var. by "wi = refl(wo | wh)", therefore, we put Jacobian "4.0 * wh_o_wo"
      vec3 wh;
      float pdf;
      vec2 u = Misc_halton2D(kNumSamplesPerFrame * iFrame + i + 1);
      Brdf_GGX_sampleCosineD(u, a, /*out*/ wh, pdf);

      vec3 wi = 2.0 * dot(wh, wo) * wh - wo; // reflect
      float n_o_wh = dot(n, wh);
      float n_o_wo = dot(n, wo);
      float n_o_wi = dot(n, wi);
      float wh_o_wo = dot(wh, wo);
      float wh_o_wi = dot(wh, wi);

      float D = Brdf_GGX_D(n_o_wh, a2);
      float Vis = Brdf_GGX_Vis(n_o_wi, n_o_wo, wh_o_wo, wh_o_wi, a2);
      float J = 4.0 * wh_o_wo;
      float ok = step(0.0, n_o_wi);

      result.x += ok * J * D * Vis * n_o_wi / pdf;                        // p
      result.y += ok * J * D * Vis * n_o_wi * pow5(1.0 - wh_o_wo) / pdf;  // q

      // [debug] different strategy of Monte carlo
      // {
      //   vec3 wi;
      //   float pdf;
      //   vec2 u = Misc_halton2D(kNumSamplesPerFrame * iFrame + i + 1);
      //   Sampling_hemisphereCosine(u, /*out*/ wi, pdf);

      //   vec3 wh = normalize(wo + wi); // half vector
      //   float n_o_wh = dot(n, wh);
      //   float n_o_wo = dot(n, wo);
      //   float n_o_wi = dot(n, wi);
      //   float wh_o_wo = dot(wh, wo);
      //   float wh_o_wi = dot(wh, wi);

      //   float D = Brdf_GGX_D(n_o_wh, a2);
      //   float Vis = Brdf_GGX_Vis(n_o_wi, n_o_wo, wh_o_wo, wh_o_wi, a2);
      //   float ok = step(0.0, n_o_wi);

      //   result.x += ok * D * Vis * n_o_wi / pdf;                        // p
      //   result.y += ok * D * Vis * n_o_wi * pow5(1.0 - wh_o_wo) / pdf;  // q
      // }
    }
    result /= float(kNumSamplesPerFrame);
    return result;
  }

  vec3 renderPixel(vec3 p) {
    p += 0.5;
    float n_o_wo = p.x / float(kSize.x);
    float roughness= p.y / float(kSize.y);
    vec2 result = integrate(n_o_wo, roughness);
    return vec3(result, 0.0);
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
