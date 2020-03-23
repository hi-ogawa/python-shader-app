//
// Orbit camera control (orbit/zoom/translate)
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
  vec3 Ssbo_camera_p;
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
      out vec4 position, out vec4 color);
  void main() {
    mainVertex(gl_VertexID, iVertexCount, iResolution.xy, iMouse, iKeyModifiers, gl_Position, Vertex_color);
  }
#endif

#ifdef COMPILE_mainFragment
  in vec4 Vertex_color;
  layout (location = 0) out vec4 Fragment_color;

  void mainFragment(out vec4 frag_color, vec4 vert_color);
  void main() {
    mainFragment(Fragment_color, Vertex_color);
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
    inout vec3 camera_p, inout vec3 lookat_p) {
  // @params
  //   control_type: in {0, 1, 2} for {Orbit, Zoom, Move}
  //   delta: For Orbit, radians it is radians
  //          For Zoom, length (only delta.y is used)
  //          For Move, length

  vec3 v = camera_p - lookat_p;
  float l = length(v);
  vec3 vn = v / l;

  // Orbit
  if (control_type == 0) {
    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 orbit_verti_axis = normalize(cross(up, v));
    mat3 orbit_verti = axisAngleTransform(orbit_verti_axis, delta.y);
    mat3 orbit_horiz = rotate3(vec3(0.0, -delta.x, 0.0));
    camera_p = lookat_p + orbit_verti * orbit_horiz * v;
  }

  // Zoom
  if (control_type == 1) {
    camera_p = lookat_p + (l - delta.y) * vn;
  }

  // Move (with lookat_p)
  if (control_type == 2) {
    mat4 camera_xform = lookatTransform_v2(camera_p, lookat_p, vec3(0.0, 1.0, 0.0));
    lookat_p = vec3(camera_xform * vec4(-delta,  -l, 1.0));
    camera_p = vec3(camera_xform * vec4(-delta, 0.0, 1.0));
  }
}

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = getViewTransform(CAMERA_ZNEAR, CAMERA_ZFAR, CAMERA_YFOV, resolution.x / resolution.y);
  mat4 camera_xform = lookatTransform_v2(Ssbo_camera_p, Ssbo_lookat_p, vec3(0.0, 1.0, 0.0));
  return view_xform * inverse(camera_xform);
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

    bool initialize = key_alt || (all(equal(Ssbo_camera_p, vec3(0.0))) && all(equal(Ssbo_lookat_p, vec3(0.0))));
    if (initialize) {
      Ssbo_camera_p = CAMERA_INIT_P;
      Ssbo_lookat_p = CAMERA_LOOKAT_P;
      return;
    }

    bool clicked, moved, released;
    vec2 mouse_delta;
    getMouseDetail(
        mouse, /*inout*/ Ssbo_mouse_down, Ssbo_mouse_down_p, Ssbo_mouse_click_p,
        /*out*/ clicked, moved, released, mouse_delta);

    vec2 delta = mouse_delta / resolution;
    if (key_control) {
      delta *= 4.0;
      updateOrbitCamera(1, delta, Ssbo_camera_p, Ssbo_lookat_p);
    } else if (key_shift) {
      updateOrbitCamera(2, delta, Ssbo_camera_p, Ssbo_lookat_p);
    } else {
      delta *= M_PI * vec2(2.0, 1.0);
      updateOrbitCamera(0, delta, Ssbo_camera_p, Ssbo_lookat_p);
    }
  }
}

void mainFragment(out vec4 frag_color, vec4 vert_color) {
  frag_color = vert_color;
}
