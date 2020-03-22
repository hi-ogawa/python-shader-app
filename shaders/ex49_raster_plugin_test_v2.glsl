//
// Test RasterPlugin
// - load triangle data as SSBO
// - compute normal and render it via RasterPlugin
// - interactive camera
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: file
      data: shaders/data/dragon2.vertex.bin
      # data: shaders/data/octahedron.vertex.bin
      align16: 12
  - type: ssbo
    params:
      binding: 1
      type: file
      data: shaders/data/dragon2.index.bin
      # data: shaders/data/octahedron.index.bin
      align16: 12
  - type: raster
    params:
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      count: "202520 * 3"  # kNumTriangles * 3
      # count: "8 * 3"
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

// cf. dragon2.stats.yaml
const int kNumVertices = 100250;
const int kNumTriangles = 202520;


//
// Shader stage specific headers
//

#ifdef COMPILE_mainVertex
  uniform vec3 iResolution;
  uniform uint iVertexCount;
  uniform vec4 iMouse;
  out vec4 Vertex_color;

  void mainVertex(
      uint vertex_id, uint vertex_count, vec2 resolution, vec4 mouse,
      out vec4 position, out vec4 color);
  void main() {
    mainVertex(gl_VertexID, iVertexCount, iResolution.xy, iMouse, gl_Position, Vertex_color);
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
// For dragon2
const vec3  CAMERA_INIT_P = vec3(-0.1, 0.3, 0.3);
const vec3  CAMERA_LOOKAT_P = vec3(-0.0058909,  0.1249391 ,-0.00460435); // center of bbox
// For octahedron (debugging)
// const vec3  CAMERA_INIT_P = vec3(3.0, 3.0, 3.0);
// const vec3  CAMERA_LOOKAT_P = vec3(0.0);
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

mat4 getVertexTransform(vec2 resolution, vec2 mouse_delta) {
  mat4 view_xform = getViewTransform(
      CAMERA_ZNEAR, CAMERA_ZFAR, CAMERA_YFOV, resolution.x / resolution.y);

  mat4 camera_xform = pivotTransform_v2(
      CAMERA_INIT_P, CAMERA_LOOKAT_P, 2.0 * M_PI * mouse_delta / resolution);

  return view_xform * inverse(camera_xform);
}


//
// Main
//

void mainVertex(
    uint vertex_id,  uint vertex_count, vec2 resolution, vec4 mouse,
    out vec4 position, out vec4 color) {

  vec2 mouse_delta = mouse.xy - abs(mouse.zw);
  mat4 xform = getVertexTransform(resolution, mouse_delta);

  uint triangle_idx = vertex_id / 3u;
  uint vertex_idx = vertex_id % 3u;
  uvec3 tri = Ssbo_indices[triangle_idx];
  vec3 vs[3];
  vs[0] = Ssbo_vertices[tri[0]];
  vs[1] = Ssbo_vertices[tri[1]];
  vs[2] = Ssbo_vertices[tri[2]];
  vec3 p = vs[vertex_idx];
  vec3 n = normalize(cross(vs[1] - vs[0], vs[2] - vs[0]));
  position = xform * vec4(p, 1.0);
  color = vec4(0.5 + 0.5 * n, 1.0);
}

void mainFragment(out vec4 frag_color, vec4 vert_color) {
  frag_color = vert_color;
}
