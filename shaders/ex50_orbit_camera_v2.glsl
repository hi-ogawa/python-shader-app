//
// Orbit camera control
// - immitate a behavior of Blender's default viewport camera)
// - coordinate grid
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: file
      data: shaders/data/octahedron.vertex.bin
      align16: 12
  - type: ssbo
    params:
      binding: 1
      type: file
      data: shaders/data/octahedron.index.bin
      align16: 12
  - type: ssbo
    params:
      binding: 2
      type: size
      size: 1024
  - type: raster
    params:
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      count: "8 * 3"
      vertex_shader: mainVertex
      fragment_shader: mainFragment
  - type: raster
    params:
      primitive: GL_LINES
      capabilities: [GL_BLEND]
      blend: true
      count: 6
      vertex_shader: mainVertex1
      fragment_shader: mainFragment1
  - type: raster
    params:
      primitive: GL_POINTS
      capabilities: [GL_PROGRAM_POINT_SIZE]
      count: 1
      vertex_shader: mainVertex2
      fragment_shader: mainFragment2

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

layout (std140, binding = 0) buffer Ssbo0 {
  vec3 Ssbo_vertices[]; // align16
};

layout (std140, binding = 1) buffer Ssbo1 {
  uvec3 Ssbo_indices[]; // align16
};

// Global state for interactive view
layout (std140, binding = 2) buffer Ssbo2 {
  bool Ssbo_mouse_down;
  vec2 Ssbo_mouse_down_p;
  vec2 Ssbo_mouse_click_p;
  mat4 Ssbo_camera_xform;
  vec3 Ssbo_lookat_p;
};


//
// Shader stage specific headers
//

#ifdef COMPILE_mainVertex
  uniform vec3 iResolution;
  uniform uint iVertexCount;
  uniform vec4 iMouse;
  uniform uint iKey;
  uniform uint iKeyModifiers;
  out vec4 Vertex_color;

  void mainVertex(
      uint vertex_id, uint vertex_count, vec2 resolution, vec4 mouse, uint key_modifiers,
      out vec4 out_position, out vec4 out_color);
  void main() {
    mainVertex(gl_VertexID, iVertexCount, iResolution.xy, iMouse, iKeyModifiers, gl_Position, Vertex_color);
  }
#endif

#ifdef COMPILE_mainFragment
  in vec4 Vertex_color;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    Fragment_color = Vertex_color;
  }
#endif

#ifdef COMPILE_mainVertex1
  uniform vec3 iResolution;
  out vec4 Vertex_color;

  void mainVertex1(uint vertex_id, vec2 resolution, out vec4 out_position, out vec4 out_color);
  void main() {
    mainVertex1(gl_VertexID, iResolution.xy, gl_Position, Vertex_color);
  }
#endif

#ifdef COMPILE_mainFragment1
  in vec4 Vertex_color;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    Fragment_color = Vertex_color;
  }
#endif

#ifdef COMPILE_mainVertex2
  uniform vec3 iResolution;
  out vec4 Vertex_color;

  void mainVertex2(uint vertex_id, vec2 resolution, out vec4 out_position, out vec4 out_color);
  void main() {
    gl_PointSize = 8.0;
    mainVertex2(gl_VertexID, iResolution.xy, gl_Position, Vertex_color);
  }
#endif

#ifdef COMPILE_mainFragment2
  in vec4 Vertex_color;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    Fragment_color = Vertex_color;
  }
#endif


//
// Utilities
//

#include "common_v0.glsl"


//
// Camera setup
//

const float CAMERA_YFOV = 39.0 * M_PI / 180.0;
const vec3  CAMERA_INIT_P = vec3(3.0, 3.0, 3.0);
const vec3  CAMERA_LOOKAT_P = vec3(0.0);
const float CAMERA_ZNEAR = 1e-3;
const float CAMERA_ZFAR  = 1e+4;

mat4 getViewTransform(float znear, float zfar, float yfov, float aspect_ratio) {
  float half_y = tan(yfov / 2.0);
  float half_x = aspect_ratio * half_y;
  float a = - (zfar + znear) / (zfar - znear);
  float b = - 2 * zfar * znear / (zfar - znear);
  float c = 1.0 / half_x;
  float d = 1.0 / half_y;
  float e = - 1.0;
  return mat4(
      c, 0, 0, 0,
      0, d, 0, 0,
      0, 0, a, e,
      0, 0, b, 0);
}

void getMouseDetail(
    vec4 mouse,
    inout bool State_mouse_down, inout vec2 State_mouse_down_p, inout vec2 State_mouse_click_p,
    out bool clicked, out bool moved, out bool released, out vec2 move_delta) {

  bool mouse_activated, mouse_down;
  vec2 last_click_pos, last_down_pos;
  getMouseState(mouse, mouse_activated, mouse_down, last_click_pos, last_down_pos);

  clicked = mouse_down && !all(equal(State_mouse_click_p, last_click_pos));
  moved = !clicked && mouse_down && !(all(equal(State_mouse_down_p, last_down_pos)));
  released = State_mouse_down && !mouse_down;
  move_delta = vec2(0.0);

  State_mouse_down = mouse_down;
  if (clicked) {
    State_mouse_click_p = State_mouse_down_p = last_click_pos;
  }
  if (moved) {
    move_delta = last_down_pos - State_mouse_down_p;
    State_mouse_down_p = last_down_pos;
  }
}

void updateOrbitCamera(
    int control_type, vec2 delta,
    inout mat4 camera_xform, inout vec3 lookat_p) {
  // assert camera_xform in Euclidian group (i.e. no scale factor)
  vec3 T = vec3(camera_xform[3]);
  vec3 X = vec3(camera_xform[0]);
  vec3 Y = vec3(camera_xform[1]);
  // vec3 Z = vec3(camera_xform[2]);
  // assert Z // (T - lookat_p)

  float L = length(T - lookat_p);

  // Orbit
  if (control_type == 0) {
    // when camera is upside-down, we flip "horizontal" orbit direction.
    float upside = sign(dot(Y, vec3(0.0, 1.0, 0.0)));

    mat3 orbit_verti = axisAngleTransform(X, delta.y);
    mat3 orbit_horiz = rotate3(vec3(0.0, upside * -delta.x, 0.0));

    // // NOTE: it's essential to apply `orbit_verti` first (since `X` has to represent instantaneous camera frame's x vector).
    mat4 camera_rel_xform = inverse(translate3(lookat_p)) * camera_xform;  // camera frame ralative to lookat_p
    camera_rel_xform = mat4(orbit_horiz * orbit_verti) * camera_rel_xform; // orbit in the frame where lookat_p is origin
    camera_xform = translate3(lookat_p) * camera_rel_xform;                // frame back to original
  }

  // Zoom
  if (control_type == 1) {
    camera_xform = camera_xform * translate3(vec3(0.0, 0.0, -delta.y));
  }

  // Move (with lookat_p)
  if (control_type == 2) {
    lookat_p += mat3(camera_xform) * vec3(-delta, 0.0);
    camera_xform = camera_xform * translate3(vec3(-delta, 0.0));
  }
}


mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = getViewTransform(CAMERA_ZNEAR, CAMERA_ZFAR, CAMERA_YFOV, resolution.x / resolution.y);
  return view_xform * inverse(Ssbo_camera_xform);
}


//
// Main
//

void getVertexData(uint vertex_id, out vec3 position, out vec3 normal) {
  uint triangle_idx = vertex_id / 3u;
  uint vertex_idx = vertex_id % 3u;
  uvec3 tri = Ssbo_indices[triangle_idx];
  vec3 vs[3];
  vs[0] = Ssbo_vertices[tri[0]];
  vs[1] = Ssbo_vertices[tri[1]];
  vs[2] = Ssbo_vertices[tri[2]];
  position = vs[vertex_idx];
  normal = normalize(cross(vs[1] - vs[0], vs[2] - vs[0]));
}

void mainVertex(
    uint vertex_id,  uint vertex_count, vec2 resolution, vec4 mouse, uint key_modifiers,
    out vec4 out_position, out vec4 out_color) {
  mat4 xform = getVertexTransform(resolution);

  vec3 p, n;
  getVertexData(vertex_id, p, n);
  out_position = xform * vec4(p, 1.0);
  out_color = vec4(0.5 + 0.5 * n, 1.0);

  // Manage global state by 1st vertex
  if (vertex_id == 0u) {
    bool key_shift =   bool(key_modifiers & 0x02000000u);
    bool key_control = bool(key_modifiers & 0x04000000u);
    bool key_alt = bool(key_modifiers & 0x08000000u);

    bool initialize = key_alt || all(equal(Ssbo_camera_xform[0], vec4(0.0)));
    if (initialize) {
      Ssbo_lookat_p = CAMERA_LOOKAT_P;
      Ssbo_camera_xform = lookatTransform_v2(
          CAMERA_INIT_P, CAMERA_LOOKAT_P, vec3(0.0, 1.0, 0.0));
      return;
    }

    bool clicked, moved, released;
    vec2 mouse_delta;
    getMouseDetail(
        mouse, /*inout*/ Ssbo_mouse_down, Ssbo_mouse_down_p, Ssbo_mouse_click_p,
        /*out*/ clicked, moved, released, mouse_delta);

    if (mouse_delta.x != 0.0 || mouse_delta.y != 0.0) {
      vec2 delta = mouse_delta / resolution;
      if (key_control) {
        delta *= 4.0;
        updateOrbitCamera(1, delta, Ssbo_camera_xform, Ssbo_lookat_p);
      } else if (key_shift) {
        updateOrbitCamera(2, delta, Ssbo_camera_xform, Ssbo_lookat_p);
      } else {
        delta *= M_PI * vec2(2.0, 1.0);
        updateOrbitCamera(0, delta, Ssbo_camera_xform, Ssbo_lookat_p);
      }
    }
  }
}

void mainVertex1(uint vertex_id, vec2 resolution, out vec4 out_position, out vec4 out_color) {
  mat4 xform = getVertexTransform(resolution);

  const float kBound = 8.0;

  vec3 p = vec3(0.0);
  uint i = vertex_id / 2;
  p[i] = 1.0;
  float s = (vertex_id % 2) == 0 ? 1.0 : -1.0;

  out_position = xform * vec4(kBound * s * p, 1.0);
  out_color = vec4(p, 0.6);
}

void mainVertex2(uint vertex_id, vec2 resolution, out vec4 out_position, out vec4 out_color) {
  mat4 xform = getVertexTransform(resolution);
  out_position = xform * vec4(Ssbo_lookat_p, 1.0);
  out_color = vec4(1.0);
};
