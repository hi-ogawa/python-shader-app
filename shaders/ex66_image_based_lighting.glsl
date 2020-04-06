//
// Image based lighting experiment
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

  # [ Sphere ]
  - type: rasterscript
    params:
      exec: from misc.mesh.src.ex02 import *; RESULT = list(map(bytes, icosphere()))
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST, GL_CULL_FACE]
      vertex_shader: mainVertexShading
      fragment_shader: mainFragmentShading
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 3) * 4)"
        Vertex_normal:   "(gl.GL_FLOAT, 3 * 4, 3, (3 + 3) * 4)"

  # [ Coordinate grid ]
  - type: rasterscript
    params:
      exec: import misc.mesh.src.ex01 as ex01; RESULT = ex01.make_coordinate_grids(axes=[0, 1, 2], bound=4)
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertexColor
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"

  # [ Quad ]
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
      type: file
      file: shaders/images/pauldebevec/uffizi_cross.hdr.latlng.hdr
      #file: shaders/images/pauldebevec/rnl_cross.hdr.latlng.hdr
      mipmap: false
      wrap: repeat
      filter: linear
      y_flip: true
      index: 0

  # [ Variables ]
  - type: uniform
    params:
      name: U_exposure
      default: 0
      min: -4
      max: +4
  - type: uniform
    params:
      name: U_exposure_diffuse
      default: -2
      min: -4
      max: +4
  - type: uniform
    params:
      name: U_metalness
      default: 0.2
      min: 0
      max: 1
  - type: uniform
    params:
      name: U_roughness
      default: 0.2
      min: 0
      max: 1

samplers: []
programs: []

offscreen_option:
  fps: 60
  num_frames: 1
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
#include "utils/misc_v0.glsl"
#include "utils/hash_v0.glsl"
#include "utils/sampling_v0.glsl"

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(0.8, 2.5, 4.0) * 2.0;
const vec3  kLookatP = vec3(0.0);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

mat3 getRayTransform(vec2 resolution) {
  return mat3(Ssbo_camera_xform) * mat3(OZN.xyy, OZN.yxy, OZN.yyz) * T_invView(kYfov, resolution);
}



//
// Programs
//

#ifdef COMPILE_mainVertexShading
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  out vec3 Interp_position;
  out vec3 Interp_normal;

  void main() {
    vec3 p = 1.5 * Vertex_position;
    Interp_position = p;
    Interp_normal = Vertex_normal;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
  }
#endif

#ifdef COMPILE_mainFragmentShading
  uniform sampler2D tex_environment;
  in vec3 Interp_position;
  in vec3 Interp_normal;
  uniform float U_roughness = 0.05;
  uniform float U_metalness = 0.1;
  uniform float U_exposure_diffuse = -1.0;
  layout (location = 0) out vec4 Fragment_color;

  vec3 Li_IBL_microfacetSpecular_monteCarlo(
      vec3 p, vec3 n, vec3 camera_p,
      vec3 color, float metalness, float roughness) {
    const int kNumSamples = 32;
    vec3 L = vec3(0.0);

    // Setup brdf related parameters
    vec3 wo = normalize(camera_p - p);
    float n_o_wo = dot(n, wo);
    float a = pow2(roughness);
    float a2 = pow2(a);
    vec3 F0 = mix(vec3(0.04), color, metalness);

    for (int i = 0; i < kNumSamples; i++) {
      // Monte carlo evaluation of microfacet specular brdf integral
      // - sample density is "rho(m) = D(m) n.wh"
      // - change var. of brdf integral by "wi = refl(wo | wh)",
      //   therefore, we put Jacobian "4.0 * wh_o_wo"
      vec3 n_wh;
      float pdf;
      vec2 u = hash42(vec4(p, float(i)));
      Brdf_GGX_sampleCosineD(u, a, n_wh, pdf);

      vec3 wh = T_zframe(n) * n_wh;
      vec3 wi = 2.0 * dot(wh, wo) * wh - wo; // reflect

      vec2 uv = T_texcoordLatLng(wi);
      vec3 Li_env = textureLod(tex_environment, T_texcoordLatLng(wi), 0.0).xyz;

      float n_o_wh = dot(n, wh);
      float n_o_wi = dot(n, wi);
      float wh_o_wo = dot(wh, wo);
      float wh_o_wi = dot(wh, wi);

      float D = Brdf_GGX_D(n_o_wh, a2);
      float Vis = Brdf_GGX_Vis(n_o_wi, n_o_wo, wh_o_wo, wh_o_wi, a2);
      vec3 F = Brdf_F_Schlick(wh_o_wo, F0);
      float J = 4.0 * wh_o_wo;

      L += J * F * D * Vis * Li_env * n_o_wi / pdf;
    }
    L /= float(kNumSamples);
    return L;
  }


  vec3 Li_IBL_diffuse_sphericalHarmonics(
      vec3 p, vec3 n, vec3 camera_p,
      vec3 color, float metalness, float roughness) {
    // python -c 'from misc.hdr.src.irradiance import *; print_M_from_file("shaders/images/pauldebevec/uffizi_cross.hdr.latlng.hdr")'
    const mat4[3] kCoeffs = mat4[3](
      mat4(
        -1.3725240,  0.0049169,  0.0811993,  0.0272505,
        0.0000000, -0.8503653,  0.1599179,  0.0834428,
        0.0000000,  0.0000000,  1.7167971,  3.7750201,
        0.0000000,  0.0000000,  0.0000000,  2.8027349
      ),
      mat4(
        -1.3546182,  0.0034420,  0.0752399,  0.0247088,
        0.0000000, -0.8444731,  0.1615555,  0.0863932,
        0.0000000,  0.0000000,  1.7046429,  3.7460140,
        0.0000000,  0.0000000,  0.0000000,  2.7187385
      ),
      mat4(
        -1.5688774,  0.0021744,  0.0872269,  0.0314687,
        0.0000000, -0.9895552,  0.2110849,  0.1161439,
        0.0000000,  0.0000000,  1.9969357,  4.3673115,
        0.0000000,  0.0000000,  0.0000000,  3.0927949
      )
    );

    // $ python -c 'from misc.hdr.src.irradiance import *; print_M_from_file("shaders/images/pauldebevec/rnl_cross.hdr.latlng.hdr")'
    // const mat4[3] kCoeffs = mat4[3](
    //   mat4(
    //     -0.4585098, -0.4986304, -0.0736364, -0.3996023,
    //     0.0000000, -0.0632669,  0.5265866,  1.0503259,
    //     0.0000000,  0.0000000,  0.1386952,  2.9306752,
    //     0.0000000,  0.0000000,  0.0000000,  3.3341365
    //   ),
    //   mat4(
    //     -0.6172074, -0.4396136,  0.1190012, -0.3153036,
    //     0.0000000, -0.1547850,  0.4682482,  1.0482650,
    //     0.0000000,  0.0000000,  0.3237984,  3.6466971,
    //     0.0000000,  0.0000000,  0.0000000,  3.7592231
    //   ),
    //   mat4(
    //     -0.7531214, -0.3209060,  0.3948001, -0.1144998,
    //     0.0000000, -0.2760057,  0.3327598,  0.8972139,
    //     0.0000000,  0.0000000,  0.5666918,  4.2192483,
    //     0.0000000,  0.0000000,  0.0000000,  3.9778852
    //   )
    // );

    vec3 brdf_diffuse = mix(color, vec3(0.0), metalness) / M_PI;
    vec4 nn = vec4(n.z, -n.x, n.y, 1.0);  // to "theta/phi" frame
    vec3 irradiance = vec3(0.0);
    irradiance[0] = dot(nn, kCoeffs[0] * nn);
    irradiance[1] = dot(nn, kCoeffs[1] * nn);
    irradiance[2] = dot(nn, kCoeffs[2] * nn);
    irradiance = max(vec3(0.0), irradiance);
    vec3 L = brdf_diffuse * irradiance;
    L *= pow(2.0, U_exposure_diffuse);
    return L;
  }

  vec3 Li_IBL(
      vec3 p, vec3 n, vec3 camera_p,
      vec3 color, float metalness, float roughness) {
    vec3 L = vec3(0.0);
    L += Li_IBL_microfacetSpecular_monteCarlo(p, n, camera_p, color, metalness, roughness);
    L += Li_IBL_diffuse_sphericalHarmonics(p, n, camera_p, color, metalness, roughness);
    return L;
  }

  void main() {
    // Setup geometry data
    vec3 p = Interp_position;
    vec3 n = normalize(Interp_normal);
    vec3 camera_p = vec3(Ssbo_camera_xform[3]);

    // Setup material
    vec3 surface_color = vec3(1.0);
    float roughness = U_roughness;
    float metalness = U_metalness;

    // Shading
    vec3 L = Li_IBL(p, n, camera_p, surface_color, metalness, roughness);
    vec3 color = encodeGamma(L);
    Fragment_color = vec4(color, 1.0);
  }
#endif


#ifdef COMPILE_mainVertexEnvironment
  layout (location = 0) in vec2 Vertex_position;
  void main() {
    gl_Position = vec4(Vertex_position, 1 - 1e-7, 1.0);
  }
#endif

#ifdef COMPILE_mainFragmentEnvironment
  uniform vec3 iResolution;
  uniform sampler2D tex_environment;
  uniform float U_exposure = 0.0;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    vec2 frag_coord = gl_FragCoord.xy;
    vec3 ray_dir = getRayTransform(iResolution.xy) * vec3(frag_coord, 1.0);
    vec3 L = textureLod(tex_environment, T_texcoordLatLng(ray_dir), 0.0).xyz;
    L *= pow(2.0, U_exposure);
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
