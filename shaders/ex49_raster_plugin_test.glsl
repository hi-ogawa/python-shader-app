//
// Test RasterPlugin
//

/*
%%config-start%%
plugins:
  - type: raster
    params:
      primitive: GL_POINTS
      count: 64
      vertex_shader: mainVertex
      fragment_shader: mainFragment

samplers: []
programs: []

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

#ifdef COMPILE_mainVertex
uniform uint iVertexCount;
uniform vec3 iResolution;
uniform float iTime;
out vec4 Vertex_color;

void mainVertex(
    uint vertex_id, uint vertex_count, vec2 resolution, float iTime,
    out vec4 position, out vec4 color);
void main() {
  gl_PointSize = 4.0;
  mainVertex(gl_VertexID, iVertexCount, iResolution.xy, iTime, gl_Position, Vertex_color);
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

#define M_PI 3.141592

vec3 hue(float t) {
  vec3 v = vec3(0.0, 1.0, 2.0) / 3.0;
  return 0.5 + 0.5 * cos(2.0 * M_PI * (t - v));
}

void mainVertex(
    uint vertex_id,  uint vertex_count, vec2 resolution, float time,
    out vec4 position, out vec4 color) {
  float t = time + float(vertex_id) / float(vertex_count);
  float r = mix(0.5, 0.9, 0.5 + 0.5 * cos(time));
  vec2 p = r * vec2(cos(2.0 * M_PI * t), sin(2.0 * M_PI * t));
  float aspect_ratio = resolution.x / resolution.y;
  p.x /= aspect_ratio;
  position = vec4(p, 0.0, 1.0);
  color = vec4(hue(t), 1.0);
}

void mainFragment(out vec4 frag_color, vec4 vert_color) {
  frag_color = vert_color;
}
