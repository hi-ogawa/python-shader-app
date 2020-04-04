//
// Shading gltf sample model (cf. https://github.com/KhronosGroup/glTF-Sample-Viewer/tree/master/src/shaders)
// - [x] texture mapping
// - [x] albedo, AO
// - [x] emissive
// - [x] normal mapping
// - [x] metallic-roughness brdf
// - [ ] image based lighting
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

  # [ Gltf mesh ]
  - type: rasterscript
    params:
      exec: |
        import numpy as np
        from misc.mesh.src import utils, loader_gltf
        verts_dict, faces = loader_gltf.load(
            'misc/bvh/data/gltf/DamagedHelmet/DamagedHelmet.gltf',
            'misc/bvh/data/gltf/DamagedHelmet/DamagedHelmet.bin')
        p_vs, n_vs, uv_vs = verts_dict['POSITION'], verts_dict['NORMAL'], verts_dict['TEXCOORD_0']
        p_vs = utils.normalize_positions(p_vs)
        rotate = np.array([[1, 0, 0], [0, 0, 1], [0,-1, 0]], np.float32)
        p_vs = p_vs @ rotate
        n_vs = n_vs @ rotate
        verts = utils.soa_to_aos(p_vs, n_vs, uv_vs)
        RESULT = bytes(verts), bytes(faces)
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST, GL_CULL_FACE]
      vertex_shader: mainVertexShading
      fragment_shader: mainFragmentShading
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 3 + 2) * 4)"
        Vertex_normal:   "(gl.GL_FLOAT, 3 * 4, 3, (3 + 3 + 2) * 4)"
        Vertex_uv:       "(gl.GL_FLOAT, 6 * 4, 2, (3 + 3 + 2) * 4)"

  # [ Coordinate grid ]
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RELOAD_REC(ex01)
        RESULT = ex01.make_coordinate_grids()
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertexColor
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"

  # [ UI state management ]
  - type: raster
    params:
      primitive: GL_POINTS
      count: 1
      vertex_shader: mainVertexUI
      fragment_shader: mainFragmentDiscard

  # [ Gltf textures ]
  - type: texture
    params:
      name: tex_albedo
      file: misc/bvh/data/gltf/DamagedHelmet/Default_albedo.jpg
      mipmap: true
      wrap: repeat
      filter: linear
      index: 0
  - type: texture
    params:
      name: tex_ao
      file: misc/bvh/data/gltf/DamagedHelmet/Default_AO.jpg
      mipmap: true
      wrap: repeat
      filter: linear
      index: 1
  - type: texture
    params:
      name: tex_normal
      type: file
      file: misc/bvh/data/gltf/DamagedHelmet/Default_normal.jpg
      mipmap: true
      wrap: repeat
      filter: linear
      index: 2
  - type: texture
    params:
      name: tex_metalRoughness
      type: file
      file: misc/bvh/data/gltf/DamagedHelmet/Default_metalRoughness.jpg
      mipmap: true
      wrap: repeat
      filter: linear
      index: 3
  - type: texture
    params:
      name: tex_emissive
      type: file
      file: misc/bvh/data/gltf/DamagedHelmet/Default_emissive.jpg
      mipmap: true
      wrap: repeat
      filter: linear
      index: 4

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
#include "utils/brdf_v0.glsl"
#include "utils/misc_v0.glsl"

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(2.0, 1.5, 4.0) * 0.8;
const vec3  kLookatP = vec3(0.0);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

#ifdef COMPILE_mainVertexShading
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  layout (location = 2) in vec2 Vertex_uv;
  out VertexInterface {
    vec3 position;
    vec3 normal;
    vec2 uv;
  } Vertex_out;

  void main() {
    vec3 p = Vertex_position;
    Vertex_out.position = p;
    Vertex_out.normal = Vertex_normal;
    Vertex_out.uv = Vertex_uv;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
  }
#endif

#ifdef COMPILE_mainFragmentShading
  uniform sampler2D tex_albedo;
  uniform sampler2D tex_ao;
  uniform sampler2D tex_normal;
  uniform sampler2D tex_metalRoughness;
  uniform sampler2D tex_emissive;
  uniform float U_scale_emissive = 12.0;

  in VertexInterface {
    vec3 position;
    vec3 normal;
    vec2 uv;
  } Fragment_in;

  layout (location = 0) out vec4 Fragment_color;

  vec3 Li(
      vec3 p, vec3 n, vec3 camera_p,
      vec3 color, float metalness, float roughness, float ao,
      vec3 emissive) {

    // Delta radiacne from camera_p
    vec3 light_p = camera_p;
    const vec3 kRadiance = vec3(1.0) * 1.5 * M_PI;

    // Uniform randiance
    const vec3 kEnvRadiance = vec3(0.2);

    vec3 wo = normalize(camera_p - p);
    vec3 wi = normalize(light_p - p);
    vec3 wh = normalize(wo + wi);

    vec3 brdf;
    brdf = Brdf_gltfMetallicRoughness(wo, wi, wh, n, color, metalness, roughness);

    // [debug]
    // brdf = Brdf_default(wo, wi, wh, n, color, 0.1);

    vec3 L = vec3(0.0);
    L += brdf * kRadiance * dot(n, wi);
    L += ao * color * (1.0 - metalness) * kEnvRadiance; // albedo = color * (1.0 - metalness)
    L += U_scale_emissive * emissive;
    return L;
  }

  vec3 applyNormalMap(vec3 p, vec2 uv, vec3 n_vert, vec3 n_tex) {
    // Map [0, 1]^3 to [-1, 1]^3
    vec3 n = 2.0 * n_tex - 1.0; // in [-1, 1]^3

    // Frame of `n` is defined as [dp_du, -dp_dv, n_vert]
    // which can be obtained by chain rule as follows:
    // (here, (a, b) represents window coordinates)
    mat2x3 dp_dab = mat2x3(dFdx(p), dFdy(p));
    mat2 duv_dab = mat2(dFdx(uv), dFdy(uv));
    mat2x3 dp_duv = dp_dab * inverse(duv_dab);

    // Transform to the frame
    vec3 n_x = + normalize(dp_duv[0]);
    vec3 n_y = - normalize(dp_duv[1]);
    mat3 n_frame = mat3(n_x, n_y, n_vert);
    return normalize(n_frame * n);
  }

  void main() {
    // Setup geometry data
    vec3 p = Fragment_in.position;
    vec3 n = normalize(Fragment_in.normal);
    vec2 uv = Fragment_in.uv;
    vec3 camera_p = vec3(Ssbo_camera_xform[3]);

    // Setup texture data
    vec3 surface_color = decodeGamma(texture(tex_albedo, uv).xyz);
    vec3 emissive = decodeGamma(texture(tex_emissive, uv).xyz);
    float ao = texture(tex_ao, uv).x;
    float metalness = texture(tex_metalRoughness, uv).z;
    float roughness = texture(tex_metalRoughness, uv).y;
    vec3 n_tex = texture(tex_normal, uv).xyz;

    // Apply normal map
    vec3 n_mapped = applyNormalMap(p, uv, n, n_tex);
    vec3 n_final;
    n_final = n_mapped;
    // [debug]
    // n_final = n;
    // n_final = mix(n, n_mapped, 0.02);

    // Shading
    vec3 L = Li(p, n_final, camera_p, surface_color, metalness, roughness, ao, emissive);
    vec3 color = encodeGamma(L);

    // [debug]
    // metalness = step(0.8, metalness);
    // color = vec3(metalness);
    // color = vec3(roughness);
    // color = vec3(ao);
    // color = n_tex;
    // color = n;
    // color = max(-n, 0.0);
    // color = n_mapped;
    // color = max(-n_mapped, 0.0);

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
