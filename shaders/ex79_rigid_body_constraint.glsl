//
// Rigid body pendulum (equality position constraint)
//

/*
%%config-start%%
plugins:
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

  # [ Geometry : constraint line ]
  - type: rasterscript
    params:
      exec: import numpy as np; RESULT = bytes(), bytes(np.uint32(np.arange(2)))
      primitive: GL_LINES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertexConstraint
      fragment_shader: mainFragmentColor
      vertex_attributes: {}

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
  vec3 Ssbo_x;
  vec3 Ssbo_v;
  vec4 Ssbo_Aq; // unit quaternion as SO(3)
  vec3 Ssbo_w;
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
const vec3  kCameraP = vec3(2.0, 0.5, 4.0) * 2.0;
const vec3  kLookatP = OZN.yxy * 1.5;

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

uniform float U_size_x = 1.0;
uniform float U_size_y = 1.0;
uniform float U_size_z = 1.0;

uniform float U_gravity = 10.0;
uniform float U_gravity_angle = 0.0;

vec3 inertiaBox(float rho, vec3 s) {
  // M = p (x * y * z)
  // I = (M / 12) * diag(y^2 + z^2, z^2 + x^2, x^2 + y^2)
  float m = rho * s.x * s.y * s.z;
  s = s * s;
  return (m / 12.0) * vec3(s.y + s.z, s.z + s.x, s.x + s.y);
}

#ifdef COMPILE_mainCompute
  void update(float t, float dt, bool init) {
    vec3 x = Ssbo_x;
    vec3 v = Ssbo_v;
    vec3 w = Ssbo_w;
    vec4 Aq = Ssbo_Aq;
    float rho = 10.0; // density kg/m^3
    vec3 size = vec3(U_size_x, U_size_y, U_size_z);
    float m = rho * size.x * size.y * size.z;
    vec3 I = inertiaBox(rho, size);

    // [ Algorithm ]
    // 0. update v, w by external force/torque (Newton-Euler equation)
    // 1. update x, A by v, w
    // 2. solve distance constraint as velocity projection and update v, w and then x, A

    // 0.
    {
      vec3 f_ext = T_rotate3(OZN.yyx * U_gravity_angle * 2.0 * M_PI) * (m * U_gravity * OZN.yzy);
      vec3 tq_ext = OZN.yyy;
      float kDumpV = 0.1;
      float kDumpW = 0.1; // TODO: probably it depends on inertia or geometry ?
      vec3 f = f_ext - kDumpV * v;
      vec3 tq = tq_ext - kDumpW * q_apply(Aq, w);
      v += dt * f / m;
      w += dt * (1.0 / I) * (q_applyInv(Aq, tq) - cross(w, I * w));
    }

    // 1.
    {
      x += dt * v;
      Aq = q_mul(Aq, q_fromAxisAngleVector(dt * w));
    }

    // 2. velocity-based projection of distance constraints
    mat3 Mv = mat3(m);
    mat3 Mw = diag(sqrt(I));
    int kNumIter = 4;
    vec3 target = OZN.yxy * 4.0;
    float target_d = 3.0;
    for (int iter = 0; iter < kNumIter; iter++) {
      // constraint is
      //   g = |p - target| - d = 0
      vec3 r = vec3(0.5);
      vec3 p = x + q_apply(Aq, r);
      float g = distance(p, target) - target_d;

      // velocity-based projection formula (TODO: write down proof)
      vec3 n = normalize(p - target);
      vec3 dv_g = dt * n;
      vec3 dw_g = dt * cross(r, q_applyInv(Aq, n));
      float q = dot(dv_g, Mv * dv_g) + dot(dw_g, Mw * dw_g);

      // velocity correction
      vec3 dv = (- g / q) * dv_g;
      vec3 dw = (- g / q) * dw_g;

      // Apply correction
      v += dv;
      w += dw;

      // Apply corresponding position correction
      // NOTE: this "position-based" correction formula is actually `dt` independent
      x += dt * dv;
      Aq = q_mul(Aq, q_fromAxisAngleVector(dt * dw));
    }

    // initial values
    if (init) {
      // [ Example 1 ]
      x = vec3(-0.5, 0.5, -0.5); // this makes g = 0 initially
      v = vec3(4.0, 0.0, 0.0);
      w = vec3(0.0, 2.0, 0.0) * 2.0 * M_PI;
      Aq = q_fromAxisAngle(vec3(0.0), 0.0);
    }

    Ssbo_x = x;
    Ssbo_v = v;
    Ssbo_w = w;
    Ssbo_Aq = Aq;
  }

  void mainCompute(/*unused*/ uvec3 comp_coord, uvec3 comp_local_coord) {
    float kTimeScale = 1.0;
    // float kTimeScale = 0.1; // slow-motion and smaller time step
    float t = Ssbo_last_time;
    float dt = kTimeScale * iTime - t;
    bool init = iFrame == 0;

    int kNumSubsteps = 1;
    // int kNumSubsteps = 8;
    float dt_substep = dt / float(kNumSubsteps);
    for (int i = 0; i < kNumSubsteps; i ++) {
      update(t, dt_substep, init);
      t += dt_substep;
    }
    if (gl_GlobalInvocationID.x == 0) {
      Ssbo_last_time = kTimeScale * iTime;
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
    vec3 scale = vec3(U_size_x, U_size_y, U_size_z);
    p = q_apply(Ssbo_Aq, scale * p) + Ssbo_x;
    n = q_apply(Ssbo_Aq, n);

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_position = p;
    Interp_normal = n;
    Interp_color = vec4(OZN.xxx, 1.0);
  }
#endif

#ifdef COMPILE_mainVertexBoxFrame
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec4 Vertex_color;
  out vec4 Interp_color;

  void main() {
    vec3 p = Vertex_position;
    p = q_apply(Ssbo_Aq, p) + Ssbo_x;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    Interp_color = Vertex_color;
  }
#endif

#ifdef COMPILE_mainVertexConstraint
  uniform vec3 iResolution;
  out vec4 Interp_color;

  void main() {
    int idx = gl_VertexID;

    vec3 target = OZN.yxy * 4.0;
    float target_d = 3.0;
    vec3 r = vec3(0.5);
    // vec3 p = Ssbo_x + Ssbo_A * r;
    vec3 p = q_apply(Ssbo_Aq, r) + Ssbo_x;

    vec4 color = vec4(0.0, 1.0, 1.0, 1.0);
    vec3 q;
    if (idx == 0) { q = p; }
    if (idx == 1) { q = target; }

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(q, 1.0);
    Interp_color = color;
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
