//
// SsboscriptPlugin test
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: size
      size: 1024
  - type: ssboscript
    params:
      bindings: [1, 2]
      exec: |
        from misc.mesh.src.data import hedron20
        verts, faces = hedron20()
        RESULT = bytes(verts), bytes(faces)
      align16: [12, 12]
  - type: raster
    params:
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      count: "3 * 6 * 2 * 4**4"
      vertex_shader: mainVertexMesh
      fragment_shader: mainFragmentMesh
  - type: raster
    params:
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST, GL_BLEND]
      blend: true
      count: 6
      vertex_shader: mainVertexGrid
      fragment_shader: mainFragmentGrid
  - type: raster
    params:
      primitive: GL_POINTS
      count: 1
      vertex_shader: mainVertexUI
      fragment_shader: mainFragmentUI

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

layout (std140, binding = 1) buffer Ssbo1 {
  vec3 Ssbo_vertices[];
};

layout (std140, binding = 2) buffer Ssbo2 {
  uvec3 Ssbo_faces[];
};


//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/ui_v0.glsl"

//
// Parameters
//

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(2.0, 0.5, 4.0);
const vec3  kLookatP = vec3(0.0);


//
// Program headers
//

#ifdef COMPILE_mainVertexMesh
  uniform vec3 iResolution;
  out vec4 Vertex_color;

  void mainVertexMesh(
      uint vertex_id, out vec4 out_position, out vec4 out_color,
      vec2 resolution);
  void main() {
    mainVertexMesh(gl_VertexID, gl_Position, Vertex_color, iResolution.xy);
  }
#endif

#ifdef COMPILE_mainFragmentMesh
  in vec4 Vertex_color;
  layout (location = 0) out vec4 Fragment_color;
  void main() {
    Fragment_color = Vertex_color;
  }
#endif

#ifdef COMPILE_mainVertexGrid
  uniform vec3 iResolution;
  out vec4 Vertex_color;

  void mainVertexGrid(
      uint vertex_id, out vec4 out_position, out vec4 out_color,
      vec2 resolution);
  void main() {
    mainVertexGrid(gl_VertexID, gl_Position, Vertex_color, iResolution.xy);
  }
#endif

#ifdef COMPILE_mainFragmentGrid
  in vec4 Vertex_color;
  layout (location = 0) out vec4 Fragment_color;
  void main() {
    Fragment_color = Vertex_color;
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

#ifdef COMPILE_mainFragmentUI
  layout (location = 0) out vec4 Fragment_color;
  void main() {
    discard;
  }
#endif


//
// Main sources
//

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

void getVertexData(uint vertex_id, out vec3 position, out vec3 normal) {
  uint triangle_idx = vertex_id / 3u;
  uint vertex_idx = vertex_id % 3u;
  uvec3 tri = Ssbo_faces[triangle_idx];
  vec3 vs[3];
  vs[0] = Ssbo_vertices[tri[0]];
  vs[1] = Ssbo_vertices[tri[1]];
  vs[2] = Ssbo_vertices[tri[2]];
  position = vs[vertex_idx];
  normal = normalize(cross(vs[1] - vs[0], vs[2] - vs[0]));
}

void mainVertexMesh(
    uint vertex_id, out vec4 out_position, out vec4 out_color,
    vec2 resolution) {
  mat4 xform = getVertexTransform(resolution);

  vec3 p, n;
  getVertexData(vertex_id, p, n);
  out_position = xform * vec4(p, 1.0);
  out_color = vec4(0.5 + 0.5 * n, 1.0);
}

void mainVertexGrid(
    uint vertex_id, out vec4 out_position, out vec4 out_color,
    vec2 resolution) {
  mat4 xform = getVertexTransform(resolution);

  const float kBound = 1e3;
  vec3 p = vec3(0.0);
  uint i = vertex_id / 2;
  p[i] = 1.0;
  float s = (vertex_id % 2) == 0 ? 1.0 : -1.0;

  out_position = xform * vec4(kBound * s * p, 1.0);
  out_color = vec4(p, 0.6);
}
