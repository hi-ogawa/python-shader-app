//
// Sampling visualization and Corput,Hammersley,Halton sequence
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: size
      size: 1024
  - type: rasterscript
    params:
      exec: RESULT = [bytes(), bytes(4)]
      instance_count: %%EVAL:2**14%%
      primitive: GL_POINTS
      capabilities: [GL_DEPTH_TEST, GL_PROGRAM_POINT_SIZE]
      vertex_shader: mainVertexDisk
      fragment_shader: mainFragmentDisk
      vertex_attributes: {}
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RESULT = ex01.make_coordinate_grids(axes=[0, 1, 2], grids=[1, 2])
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

  - type: uniform
    params:
      name: U_num_samples
      default: 512
      min: 1
      max: 2048

  - type: uniform
    params:
      name: U_mode
      default: 2
      min: 0
      max: 5

  - type: uniform
    params:
      name: U_mode_sequence
      default: 0
      min: 0
      max: 2

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
#include "utils/sampling_v0.glsl"
#include "utils/misc_v0.glsl"

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(0.5, 0.5, 2.0) * 2.0;
const vec3  kLookatP = vec3(0.0, 0.0, 0.0);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

#ifdef COMPILE_mainVertexDisk
  uniform vec3 iResolution;
  uniform float U_num_samples;
  uniform float U_mode = 0.0;
  uniform float U_mode_sequence = 0.0;
  out vec3 Interp_position;
  out flat uint Interp_instanceId;

  vec3 getPosition() {
    vec2 q;
    if (U_mode_sequence < 1.0) {
      q = Misc_hammersley2D(gl_InstanceID + 1, uint(U_num_samples));
    } else {
      q = Misc_halton2D(gl_InstanceID + 1);
    }

    vec3 p;
    if (U_mode < 1.0) {
      p = vec3(q * 2.0 - 1.0, 0.0);
    } else
    if (U_mode < 2.0) {
      p = vec3(T_squareToDisk(q), 0.0);
    } else

    // With square-disk isotopy
    if (U_mode < 2.5) {
      float pdf;
      q = T_squareToDisk_polarUniform(q);
      Sampling_hemisphereCosine(q, /*out*/ p, pdf);
    } else
    if (U_mode < 3.0) {
      float pdf;
      q = T_squareToDisk_polarUniform(q);
      Sampling_hemisphereUniform(q, /*out*/ p, pdf);
    } else
    if (U_mode < 3.5) {
      float pdf;
      q = T_squareToDisk_polarUniform(q);
      Sampling_sphereUniform(q, /*out*/ p, pdf);
    } else

    // Without square-disk isotopy
    if (U_mode < 4.0) {
      float pdf;
      Sampling_hemisphereCosine(q, /*out*/ p, pdf);
    } else
    if (U_mode < 4.5) {
      float pdf;
      Sampling_hemisphereUniform(q, /*out*/ p, pdf);
    } else
    if (U_mode < 5.0) {
      float pdf;
      Sampling_sphereUniform(q, /*out*/ p, pdf);
    }
    return p;
  }

  void main() {
    gl_PointSize = 8.0;
    vec3 p = getPosition();
    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_instanceId = gl_InstanceID;
    Interp_position = p;
  }
#endif

#ifdef COMPILE_mainFragmentDisk
  uniform vec3 iResolution;
  uniform float U_num_samples;
  in vec3 Interp_position;
  in flat uint Interp_instanceId;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    if (!(Interp_instanceId + 1 <= U_num_samples)) {
      discard; return;
    }
    vec3 color = vec3(1.0);
    color = Misc_hue(float(Interp_instanceId) / U_num_samples);

    // [when gl_PointSize > 1.0]
    float fac = 1.0 - smoothstep(0.3, 0.7, length(gl_PointCoord - 0.5));
    Fragment_color = vec4(color * fac, 1.0);
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
