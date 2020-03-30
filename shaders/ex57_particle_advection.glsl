//
// Advect particle by procedual flow
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: size
      size: 1024
  - type: ssbo
    params:
      binding: 1
      type: size
      size: "4 * 4 * 2**12" # vec4 * 2**12
  - type: ssbo
    params:
      binding: 2
      type: size
      size: "4 * 4 * 2**12" # vec4 * 2**12
  - type: rasterscript
    params:
      exec: RESULT = [bytes(), bytes(4)]
      instance_count: "2**14"
      primitive: GL_POINTS
      capabilities: [GL_DEPTH_TEST, GL_PROGRAM_POINT_SIZE]
      blend: true
      vertex_shader: mainVertexDisk
      fragment_shader: mainFragmentDisk
      vertex_attributes: {}
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RESULT = ex01.make_coordinate_grids()
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertexColor
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"
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
    local_size: [1, 1, 1]
    global_size: "[2**14, 1, 1]"
    samplers: []

offscreen_option:
  fps: 60
  num_frames: 24
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

layout (std140, binding = 1) buffer Ssbo1 {
  vec3 Ssbo_positions[];
};

layout (std140, binding = 2) buffer Ssbo2 {
  vec3 Ssbo_states[];
};


//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/ui_v0.glsl"
#include "utils/brdf_v0.glsl"
#include "utils/hash_v0.glsl"
#include "utils/sampling_v0.glsl"

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(2.0, 1.5, 4.0) * 0.5;
const vec3  kLookatP = vec3(0.5);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

#ifdef COMPILE_mainCompute
  // (LeVeque) High-Resolution Conservative Algorithms for Advection in Incompressible Flow
  // https://epubs.siam.org/doi/10.1137/0733033?mobileUi=0&
  vec3 flow_LeVeque2(vec3 p) {
    vec3 v;
    v.x = + pow2(sin(M_PI * p.x)) * sin(2.0 * M_PI * p.y);
    v.y = - pow2(sin(M_PI * p.y)) * sin(2.0 * M_PI * p.x);
    v.z = 0.0;
    return v;
  }

  vec3 flow_LeVeque3(vec3 p) {
    vec3 v;
    v.x = + 2.0 * pow2(sin(M_PI * p.x)) * sin(2.0 * M_PI * p.y) * sin(2.0 * M_PI * p.z);
    v.y = - 1.0 * pow2(sin(M_PI * p.y)) * sin(2.0 * M_PI * p.x) * sin(2.0 * M_PI * p.z);
    v.z = - 1.0 * pow2(sin(M_PI * p.z)) * sin(2.0 * M_PI * p.x) * sin(2.0 * M_PI * p.y);
    v *= sin(2.0 * M_PI * iTime / 8.0);
    return v;
  }

  vec3 flow_random(vec3 p, vec2 seed) {
    vec2 u = hash22(seed);
    vec3 q;
    float pdf;
    Sampling_sphereUniform(u, /*out*/ q, pdf);
    return q;
  }

  vec3 advect(vec3 p, vec2 seed) {
    vec3 v;
    // v = flow_random(p, seed);
    v = flow_LeVeque3(p);
    p += 0.005 * v;
    return p;
  }

  vec3 init(vec3 p, uint i) {
    p = hash13(float(i));
    Ssbo_states[i] = p;
    return p * 0.5 + 0.25;
  }

  void mainCompute(uvec3 comp_coord, uvec3 comp_local_coord) {
    uint i = comp_coord.x;
    vec3 p = Ssbo_positions[i];
    p = advect(p, vec2(i, iFrame));
    if (iFrame == 0) {
      p = init(p, i);
    }
    Ssbo_positions[i] = p;
  }
#endif


#ifdef COMPILE_mainVertexDisk
  uniform vec3 iResolution;
  out vec3 Interp_position;
  out flat uint Interp_instanceId;

  void main() {
    gl_PointSize = 2.0;
    Interp_position = Ssbo_positions[gl_InstanceID];
    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(Interp_position, 1.0);
    Interp_instanceId = gl_InstanceID;
  }
#endif

#ifdef COMPILE_mainFragmentDisk
  uniform vec3 iResolution;
  in vec3 Interp_position;
  in flat uint Interp_instanceId;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    float fac = 1.0 - smoothstep(0.3, 0.6, length(gl_PointCoord - 0.5));
    vec3 q = Ssbo_states[Interp_instanceId]; // in [0, 1]^3
    q = smoothstep(vec3(-0.5), vec3(1.0), q); // squash gray

    vec3 color;
    // [color cube]
    color = q;
    // [white points]
    // color = vec3(1.0);

    // [when gl_PointSize > 1.0]
    // 1. make outline
    color *= fac;
    Fragment_color = vec4(color, 1.0);
    // 2. make it blend
    // Fragment_color = vec4(color, fac);
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
    Interp_color = Vertex_color;
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
