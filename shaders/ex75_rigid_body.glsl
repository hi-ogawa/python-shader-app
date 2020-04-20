//
// Torque free solution of Euler's equation (rigid body theory)
// i.e.
//   Dw = - I^-1 cross(w, Iw)
//   DA = A Cw  (where Cw is s.t. Cw v = cross(w, x))
//
// This demonstrates "Tennis racket theorem" where
//   Ix > Iy > Iz with initial value w ~ ey
//

/*
%%config-start%%
plugins:
  # [ Variable ]
  - type: uniformlist
    params:
      name: ['U_size_x', 'U_size_y', 'U_size_z']
      default: [0.5, 1.0, 2.0]
      min: [0.1, 0.1, 0.1]
      max: [4.0, 4.0, 4.0]

  # [ Buffer ]
  - type: ssbo
    params: { binding: 1, type: size, size: 1024 }

  # [ Geometry : box ]
  - type: rasterscript
    params:
      exec: |
        from misc.mesh.src import data, utils
        p_vs, faces = data.cube()
        p_vs *= 0.5  # in [-0.5, 0.5]^3
        RESULT = list(map(bytes, utils.finalize(p_vs, faces, smooth=False)))
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertexBox
      fragment_shader: mainFragmentDefault
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 3) * 4)"
        Vertex_normal:   "(gl.GL_FLOAT, 3 * 4, 3, (3 + 3) * 4)"

  # [ Geometry : iso energy surface ]
  - type: rasterscript
    params:
      exec: |
        from misc.mesh.src import data, utils
        p_vs, faces = data.hedron20()
        for _ in range(4): p_vs, faces = utils.geodesic_subdiv(p_vs, faces)
        verts, faces = utils.finalize(p_vs, faces, smooth=True)
        RESULT = bytes(verts), bytes(faces)
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST, GL_CULL_FACE]
      blend: true
      vertex_shader: mainVertexSurfaceEnergy
      fragment_shader: mainFragmentDefault
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 3) * 4)"
        Vertex_normal:   "(gl.GL_FLOAT, 3 * 4, 3, (3 + 3) * 4)"

  # [ Geometry : iso angular momentum magnitude surface ]
  - type: rasterscript
    params:
      exec: |
        from misc.mesh.src import data, utils
        p_vs, faces = data.hedron20()
        for _ in range(3): p_vs, faces = utils.geodesic_subdiv(p_vs, faces)
        verts, faces = utils.finalize(p_vs, faces, smooth=True)
        RESULT = bytes(verts), bytes(faces)
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST, GL_CULL_FACE]
      blend: true
      vertex_shader: mainVertexSurfaceMomentum
      fragment_shader: mainFragmentDefault
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 3) * 4)"
        Vertex_normal:   "(gl.GL_FLOAT, 3 * 4, 3, (3 + 3) * 4)"

  # [ Geometry : angular velocity/momentum vector ]
  - type: rasterscript
    params:
      exec: import numpy as np; RESULT = bytes(), bytes(np.uint32(np.arange(4)))
      primitive: GL_LINES
      vertex_shader: mainVertexVector
      fragment_shader: mainFragmentColor
      vertex_attributes: {}

  # [ Geometry : box frame ]
  - type: rasterscript
    params:
      exec: |
        from misc.mesh.src import data, utils
        import numpy as np; Np = np.array
        vs1 = Np([
          [0, 0, 0], [1, 0, 0],
          [0, 0, 0], [0, 1, 0],
          [0, 0, 0], [0, 0, 1],
        ], np.float32)
        vs2 = Np([
          [1, 0, 0, 1], [1, 0, 0, 1],
          [0, 1, 0, 1], [0, 1, 0, 1],
          [0, 0, 1, 1], [0, 0, 1, 1],
        ], np.float32)
        vs1 *= 0.8
        verts = utils.soa_to_aos(vs1, vs2)
        indices = np.arange(2 * len(verts), dtype=np.uint32)
        RESULT = list(map(bytes, [verts, indices]))
      primitive: GL_LINES
      vertex_shader: mainVertexBoxFrame
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"

  # [ Coordinate grid ]
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RESULT = ex01.make_coordinate_grids(axes=[0, 1, 2], grids=[1])
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertexColor
      fragment_shader: mainFragmentColor
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"

  # [ UI state management ]
  - type: ssbo
    params: { binding: 0, type: size, size: 1024 }
  - type: raster
    params: { primitive: GL_POINTS, count: 1, vertex_shader: mainVertexUI, fragment_shader: mainFragmentDiscard }

samplers: []
programs:
  - name: mainCompute
    type: compute
    local_size: [1, 1, 1]
    global_size: [1, 1, 1]
    samplers: []

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
  float Ssbo_last_time;
  vec3 Ssbo_w;
  mat3 Ssbo_A;
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
const vec3  kLookatP = vec3(0.0);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

// Ix : Iy : Iz = 20 : 16 : 4 = 5 : 4 : 1
uniform float U_size_x = 0.5;
uniform float U_size_y = 1.0;
uniform float U_size_z = 2.0;

vec3 inertiaBox(vec3 s) {
  // M = p (x * y * z)
  // I = (M / 12) * diag(y^2 + z^2, z^2 + x^2, x^2 + y^2)
  s = s * s;
  return vec3(s.y + s.z, s.z + s.x, s.x + s.y);
}

#ifdef COMPILE_mainCompute

  // Explicit Runge-Kutta 4th order
  //   F : float, TYPE_X -> TYPE_X
  //   X : TYPE_X (inout)
  #define RK4(TYPE_X, F, T, X, DT)                                       \
    {                                                                    \
      TYPE_X K1 = F(T             , X                  );                \
      TYPE_X K2 = F(T + 1./2. * DT, X + 1./2. * dt * K1);                \
      TYPE_X K3 = F(T + 1./2. * DT, X + 1./2. * dt * K2);                \
      TYPE_X K4 = F(T + 1.    * DT, X + 1.    * dt * K3);                \
      X = X + DT * (1./6. * K1 + 2./6. * K2 + 2./6. * K3 + 1./6. * K4);  \
    }                                                                    \

  vec3 f(float t, vec3 w) {
    vec3 I = inertiaBox(vec3(U_size_x, U_size_y, U_size_z));
    vec3 dw = - cross(w, I * w) / I;
    return dw;
  }

  void update(float t, float dt, bool init) {
    vec3 w = Ssbo_w;
    mat3 A = Ssbo_A;

    RK4(vec3, f, t, w, dt);
    A = A * T_axisAngle(normalize(w), dt * length(w));

    if (init) {
      w = normalize(vec3(0.0, 1.0, 0.1));
      w *= 2.0 * M_PI / 3.0;
      A = mat3(OZN.xyy, OZN.yxy, OZN.yyx);
    }
    Ssbo_w = w;
    Ssbo_A = A;
  }

  void mainCompute(/*unused*/ uvec3 comp_coord, uvec3 comp_local_coord) {
    float t = Ssbo_last_time;
    float dt = iTime - t;
    bool init = iFrame == 0;
    update(t, dt, init);
    if (gl_GlobalInvocationID.x == 0) {
      Ssbo_last_time = iTime;
    }
  }
#endif


#ifdef COMPILE_mainVertexBox
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  out vec3 Interp_normal;
  out vec3 Interp_position;
  out float Interp_alpha;
  out vec4 Interp_color;

  void main() {
    vec3 p = Vertex_position;
    vec3 n = Vertex_normal;
    vec3 size = vec3(U_size_x, U_size_y, U_size_z);
    p = size * p;
    p = Ssbo_A * p;
    n = Ssbo_A * n;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_position = p;
    Interp_normal = n;
    Interp_color = vec4(OZN.xxx, 1.0);
  }
#endif

#ifdef COMPILE_mainVertexSurfaceEnergy
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  out vec3 Interp_normal;
  out vec3 Interp_position;
  out float Interp_alpha;
  out vec4 Interp_color;

  void main() {
    vec3 p = Vertex_position;
    vec3 n = Vertex_normal;

    vec3 I = inertiaBox(vec3(U_size_x, U_size_y, U_size_z));
    vec3 w = Ssbo_w;
    vec3 m = I * w;
    float E2 = dot(w, I * w);
    vec3 ellipsoid = sqrt(E2 * I); // E2 = |mx/Ix|^2 + |my/Iy|^2 + |mz/Iz|^2
    ellipsoid /= length(m); // unit where |m| is 1 (arbitrary shrinking to fit display)

    p = ellipsoid * p;
    p = Ssbo_A * p;
    n = Ssbo_A * n;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_position = p;
    Interp_normal = n;
    Interp_color = vec4(OZN.xyy, 0.2);
  }
#endif

#ifdef COMPILE_mainVertexSurfaceMomentum
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  out vec3 Interp_normal;
  out vec3 Interp_position;
  out float Interp_alpha;
  out vec4 Interp_color;

  void main() {
    vec3 p = Vertex_position;
    vec3 n = Vertex_normal;

    p = Ssbo_A * p;
    n = Ssbo_A * n;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_position = p;
    Interp_normal = n;
    Interp_color = vec4(OZN.xxx, 0.4);
  }
#endif

#ifdef COMPILE_mainVertexVector
  uniform vec3 iResolution;
  out vec4 Interp_color;

  void main() {
    vec3 p;
    vec4 color;
    vec3 I = inertiaBox(vec3(U_size_x, U_size_y, U_size_z));
    vec3 w = Ssbo_w;
    vec3 m = I * w;
    if (gl_VertexID < 2) {
      p = (gl_VertexID % 2 == 0) ? OZN.yyy : normalize(w);
      color = vec4(0.0, 1.0, 1.0, 1.0);
    } else
    if (gl_VertexID < 4) {
      p = (gl_VertexID % 2 == 0) ? OZN.yyy : normalize(m);
      color = vec4(1.0, 0.0, 1.0, 1.0);
    }
    p = Ssbo_A * p;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_color = color;
  }
#endif

#ifdef COMPILE_mainVertexBoxFrame
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec4 Vertex_color;
  out vec4 Interp_color;

  void main() {
    vec3 p = Vertex_position;
    p = Ssbo_A * p;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_color = Vertex_color;
  }
#endif

#ifdef COMPILE_mainFragmentDefault
  in vec3 Interp_normal;
  in vec3 Interp_position;
  in float Interp_alpha;
  in vec4 Interp_color;
  layout (location = 0) out vec4 Fragment_color;

  vec3 Li(vec3 p, vec3 n, vec3 camera_p, vec3 surface_color) {
    const vec3 kRadienceEnv = vec3(0.15);
    const vec3 kRadiance = vec3(0.6) * M_PI;

    vec3 light_p = camera_p;  // Directional light from camera_p
    vec3 wo = normalize(camera_p - p);
    vec3 wi = normalize(light_p - p);
    vec3 wh = normalize(wo + wi);
    vec3 brdf = Brdf_default(wo, wi, wh, n, surface_color, 0.1);
    vec3 L = vec3(0.0);
    L += brdf * kRadiance * clamp0(dot(n, wi));
    L += surface_color * kRadienceEnv;
    return L;
  }

  void main() {
    vec3 p = Interp_position;
    vec3 n = normalize(Interp_normal);
    vec3 camera_p = vec3(Ssbo_camera_xform[3]);
    vec3 surface_color = Interp_color.xyz;
    vec3 color = Li(p, n, camera_p, surface_color);
    color = pow(color, vec3(1 / 2.2));
    Fragment_color = vec4(color, Interp_color.w);
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
