//
// Isosurface mesh by marching cube
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
        table = table_marching_cube
        stats, vert_data, face_data = [
            np.uint32(x) for x in utils.make_data(table.data) ]
        RESULT = bytes(stats), bytes(vert_data), bytes(face_data)

  # [ Geometry ]
  - type: rasterscript
    params:
      exec: |
        import numpy as np
        indices = np.arange(32**3, dtype=np.uint32)
        RESULT = [bytes(), bytes(indices)]
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
    params: { name: U_threshold, default: 0, min: -1, max: 1}

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
const vec3  kCameraP = vec3(2.0, 1.5, 4.0) * 0.7;
const vec3  kLookatP = vec3(0.5);

// cube grid
const int kResolution = 32;


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
  uniform float U_threshold = 0.0;
  uniform float iTime;

  layout(points) in;
  layout(triangle_strip, max_vertices = 18) out;
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

  void interpolateData(
      float f0, float f1, float threshold,
      vec3 p0, vec3 p1, vec3 grad_f0, vec3 grad_f1,
      out vec3 p, out vec3 n) {
    float t = (threshold - f0) / (f1 - f0);
    p = mix(p0, p1, t);
    n = normalize(mix(grad_f0, grad_f1, t));
  }

  float Sdf_sphere(vec3 p, float r) {
    return length(p) - r;
  }

  float Sdf_torus(vec3 p, float r1, float r2) {
    return length(vec2(length(p.xz) - r1, p.y)) - r2;
  }

  float SdfOp_smoothMin(float d1, float d2, float k) {
    float z = max(1.0 - abs(d1 - d2) / k, 0.0);
    float fac = 0.5 * k * pow2(z) / 2.0;
    return min(d1, d2) - fac;
  }

  float evaluateSdf(vec3 p) {
    float sd = 1e7;
    {
      vec3 c = vec3(0.5);
      c.x += sin(2.0 * M_PI * iTime / 2.0) * 0.25;
      c.y += sin(2.0 * M_PI * iTime / 3.0) * 0.25;
      c.z += sin(2.0 * M_PI * iTime / 1.0) * 0.25;
      float r = 0.2;
      sd = SdfOp_smoothMin(sd, Sdf_sphere(p - c, r), 0.2);
    }
    {
      vec3 c = vec3(0.5);
      vec3 q = T_rotate3(2.0 * M_PI * iTime * vec3(0.5, 0.0, 0.6)) * (p - c);
      sd = SdfOp_smoothMin(sd, Sdf_torus(q, 0.35, 0.1), 0.2);
    }
    return sd;
  }

  vec3 evaluateGradSdf(vec3 p) {
    // Regular tetrahedron from cube's 4 corners
    const mat4x3 A = mat4x3(OZN.xxx, OZN.zzx, OZN.xzz, OZN.zxz) / sqrt(3.0);
    const mat3x4 AT = transpose(A);
    const mat3x3 inv_A_AT = inverse(A * AT);
    const mat4x3 B = inv_A_AT * A;
    const float kDelta = 1e-3;
    vec4 AT_G = vec4(
        evaluateSdf(p + kDelta * A[0]),
        evaluateSdf(p + kDelta * A[1]),
        evaluateSdf(p + kDelta * A[2]),
        evaluateSdf(p + kDelta * A[3]));
    return normalize(B * AT_G);
  }

  void makeGeometry(vec3 p, vec3 dp) {
    mat4 xform = getVertexTransform(iResolution.xy);
    float threshold = U_threshold;

    float f[8];
    vec3 grad_f[8];
    for (int i = 0; i < 8; i++) {
      vec3 q = p + dp * kCornerPositions[i];
      f[i] = evaluateSdf(q);
      grad_f[i] = evaluateGradSdf(q);
    }

    uint key = 0u;
    for (uint i = 0u; i < 8u; i++) {
      key |= uint(f[i] < threshold) << i;
    }

    int num_verts    = Ssbo_marching_cube_data1[4 * key + 0];
    int num_faces    = Ssbo_marching_cube_data1[4 * key + 1];
    int offset_verts = Ssbo_marching_cube_data1[4 * key + 2];
    int offset_faces = Ssbo_marching_cube_data1[4 * key + 3];

    for (int i = 0; i < num_faces; i++) {
      vec3 ps[3];
      vec3 ns[3];
      for (int j = 0; j < 3; j++) {
        int idx = Ssbo_marching_cube_data3[3 * (i + offset_faces) + j];
        int v0 = Ssbo_marching_cube_data2[2 * (idx + offset_verts) + 0];
        int v1 = Ssbo_marching_cube_data2[2 * (idx + offset_verts) + 1];
        if (v0 == v1) {
          ps[j] = kCornerPositions[v0];
          ns[j] = grad_f[v0];
          continue;
        }
        interpolateData(
            f[v0], f[v1], threshold,
            kCornerPositions[v0], kCornerPositions[v1],
            grad_f[v0], grad_f[v1], ps[j], ns[j]);
      }

      for (int j = 0; j < 3; j++) {
        vec3 q = p + dp * ps[j];
        Interp_position = q;
        Interp_normal = ns[j];
        gl_Position = xform * vec4(q, 1.0);
        EmitVertex();
      }
      EndPrimitive();
    }
  }

  void main() {
    int idx = gl_PrimitiveIDIn;
    int r = kResolution;
    vec3 p = vec3(((idx / ivec3(1.0, r, r * r)) % r)) / float(r);
    vec3 dp = vec3(1.0) / r;
    makeGeometry(p, dp);
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
