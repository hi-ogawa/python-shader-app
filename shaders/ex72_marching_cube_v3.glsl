//
// Marching cube table visualization (generate triangle from geometry shader)
//


/*
%%config-start%%
plugins:
  # [ Marching cube table ]
  - type: ssboscript
    params:
      bindings: [2, 3, 4]
      exec: |
        import numpy as np
        from misc.marching_cube.src import utils, table_all_faces, table_marching_cube
        #table = table_all_faces
        table = table_marching_cube
        stats, vert_data, face_data = [
            np.uint32(x) for x in utils.make_data(table.data) ]
        RESULT = bytes(stats), bytes(vert_data), bytes(face_data)

  - type: rasterscript
    params:
      exec: RESULT = [bytes(), bytes(4)] # uint32
      primitive: GL_POINTS
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertex
      geometry_shader: mainGeometry
      fragment_shader: mainFragmentShading
      vertex_attributes: {}

  # [ Coordinate grid ]
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RESULT = ex01.make_coordinate_grids(axes=[0, 1, 2], bound=4)
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertexColor
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"

  # [ Uniforms ]
  - type: uniform
    params: { name: U_f000, default: 1.0, min: 0, max: 1}
  - type: uniform
    params: { name: U_f100, default: 0.0, min: 0, max: 1}
  - type: uniform
    params: { name: U_f110, default: 0.2, min: 0, max: 1}
  - type: uniform
    params: { name: U_f010, default: 1.0, min: 0, max: 1}
  - type: uniform
    params: { name: U_f001, default: 1.0, min: 0, max: 1}
  - type: uniform
    params: { name: U_f101, default: 1.0, min: 0, max: 1}
  - type: uniform
    params: { name: U_f111, default: 1.0, min: 0, max: 1}
  - type: uniform
    params: { name: U_f011, default: 0.2, min: 0, max: 1}
  - type: uniform
    params: { name: U_threshold, default: 0.5, min: 0, max: 1}


  # [ UI ]
  - type: ssbo
    params:
      binding: 0
      type: size
      size: 1024
  - type: raster
    params:
      primitive: GL_POINTS
      count: 1
      vertex_shader: mainVertexUI
      fragment_shader: mainFragmentDiscard

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

layout (std430, binding = 2) readonly buffer Ssbo2 {
  int Ssbo_marching_cube_data1[];
};

layout (std430, binding = 3) readonly buffer Ssbo3 {
  int Ssbo_marching_cube_data2[];
};

layout (std430, binding = 4) readonly buffer Ssbo4 {
  int Ssbo_marching_cube_data3[];
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
const vec3  kCameraP = vec3(2.0, 1.5, 4.0) * 1.0;
const vec3  kLookatP = vec3(0.5);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

#ifdef COMPILE_mainVertex
  void main() {}
#endif

#ifdef COMPILE_mainGeometry
  uniform vec3 iResolution;
  uniform float U_f000 = 1.0;
  uniform float U_f100 = 0.0;
  uniform float U_f110 = 0.2;
  uniform float U_f010 = 1.0;
  uniform float U_f001 = 1.0;
  uniform float U_f101 = 1.0;
  uniform float U_f111 = 1.0;
  uniform float U_f011 = 0.2;
  uniform float U_threshold = 0.5;

  layout(points) in;
  // for `table_all_faces`     => 28 * 3 = 84
  // for `table_marching_cube` => 6 * 3  = 18
  layout(triangle_strip, max_vertices = 128) out;
  out vec3 Interp_position;
  out vec3 Interp_normal;

  vec3 kCornerPositions[] = vec3[](
    vec3(0.0, 0.0, 0.0),
    vec3(1.0, 0.0, 0.0),
    vec3(1.0, 1.0, 0.0),
    vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 1.0),
    vec3(1.0, 0.0, 1.0),
    vec3(1.0, 1.0, 1.0),
    vec3(0.0, 1.0, 1.0)
  );

  vec3 interpolatePosition(int v0, int v1, float f0, float f1, float threshold) {
    if (v0 == v1) {
      return kCornerPositions[v0];
    }
    vec3 p0 = kCornerPositions[v0];
    vec3 p1 = kCornerPositions[v1];
    vec3 p = p0 + (threshold - f0) / (f1 - f0) * (p1 - p0);
    return p;
  }

  void main() {
    mat4 xform = getVertexTransform(iResolution.xy);
    float f[8] = float[8](
      U_f000, U_f100, U_f110, U_f010,
      U_f001, U_f101, U_f111, U_f011
    );
    float threshold = U_threshold;

    uint key = 0u;
    key |= uint(threshold < f[0]) << 0u;
    key |= uint(threshold < f[1]) << 1u;
    key |= uint(threshold < f[2]) << 2u;
    key |= uint(threshold < f[3]) << 3u;
    key |= uint(threshold < f[4]) << 4u;
    key |= uint(threshold < f[5]) << 5u;
    key |= uint(threshold < f[6]) << 6u;
    key |= uint(threshold < f[7]) << 7u;

    int num_verts    = Ssbo_marching_cube_data1[4 * key + 0];
    int num_faces    = Ssbo_marching_cube_data1[4 * key + 1];
    int offset_verts = Ssbo_marching_cube_data1[4 * key + 2];
    int offset_faces = Ssbo_marching_cube_data1[4 * key + 3];

    for (int i = 0; i < num_faces; i++) {
      vec3 ps[3];
      for (int j = 0; j < 3; j++) {
        int idx = Ssbo_marching_cube_data3[3 * (i + offset_faces) + j];
        int v0 = Ssbo_marching_cube_data2[2 * (idx + offset_verts) + 0];
        int v1 = Ssbo_marching_cube_data2[2 * (idx + offset_verts) + 1];
        ps[j] = interpolatePosition(v0, v1, f[v0], f[v1], threshold);
      }
      vec3 n = cross(ps[1] - ps[0], ps[2] - ps[0]);

      for (int j = 0; j < 3; j++) {
        Interp_position = ps[j];
        Interp_normal = n;
        gl_Position = xform * vec4(ps[j], 1.0);
        EmitVertex();
      }
      EndPrimitive();
    }
  }
#endif

#ifdef COMPILE_mainFragmentShading
  in vec3 Interp_normal;
  in vec3 Interp_position;

  vec3 Li(vec3 p, vec3 n, vec3 camera_p, vec3 color) {
    const vec3 kRadiance = vec3(1.0) * M_PI;

    vec3 light_p = camera_p;  // Directional light from camera_p
    vec3 wo = normalize(camera_p - p);
    vec3 wi = normalize(light_p - p);
    vec3 wh = normalize(wo + wi);
    vec3 brdf = Brdf_default(wo, wi, wh, n, color, 0.1);

    vec3 L = vec3(0.0);
    L += brdf * kRadiance * clamp0(dot(n, wi));
    return L;
  }

  layout (location = 0) out vec4 Fragment_color;
  void main() {
    vec3 p = Interp_position;
    vec3 camera_p = vec3(Ssbo_camera_xform[3]);
    vec3 n = normalize(Interp_normal);
    float orientation = sign(dot(n, camera_p - p));
    n *= orientation;
    vec3 surface_color = mix(vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), step(0.0, orientation));
    vec3 color = Li(p, n, camera_p, surface_color);
    color = pow(color, vec3(1 / 2.2));
    Fragment_color = vec4(color, 1.0);
  }
#endif


//
// program: grid
//

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


//
// program: ui
//

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
