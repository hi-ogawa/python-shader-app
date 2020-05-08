//
// Rigid body (collision reaction and contact constraint)
//
// TODO: compare with analytically solved example
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
  mat3 Ssbo_A;
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

// [ Inertia Ix > Iy > Iz ]
// uniform float U_size_x = 0.1;
// uniform float U_size_y = 1.0;
// uniform float U_size_z = 10.0;

// uniform float U_size_x = 0.2;
// uniform float U_size_y = 1.0;
// uniform float U_size_z = 4.0;

// [ Inertia Iy >> Ix, Iz ]
// uniform float U_size_x = 4.0;
// uniform float U_size_y = 1.0;
// uniform float U_size_z = 4.0;

// [ Unit cube ]
uniform float U_size_x = 1.0;
uniform float U_size_y = 1.0;
uniform float U_size_z = 1.0;

uniform float U_gravity = 9.8;

vec3 inertiaBox(float rho, vec3 s) {
  // M = p (x * y * z)
  // I = (M / 12) * diag(y^2 + z^2, z^2 + x^2, x^2 + y^2)
  float m = rho * s.x * s.y * s.z;
  s = s * s;
  return (m / 12.0) * vec3(s.y + s.z, s.z + s.x, s.x + s.y);
}

#ifdef COMPILE_mainCompute
  void collectBoxProximities(
      vec3 c, vec3 size, mat3 A, out int num_hits, out vec3 hits[8]) {
    num_hits = 0;
    const vec3 kCorners[8] = vec3[](
      OZN.xxx, OZN.zxx, OZN.zzx, OZN.xzx,
      OZN.xxz, OZN.zxz, OZN.zzz, OZN.xzz);
    for (int i = 0; i < 8; i++) {
      vec3 r = size * kCorners[i] / 2.0;
      vec3 p = A * r + c;
      // Ground at y = 0
      if (p.y <= 0.1) {
        hits[num_hits] = r;
        num_hits++;
      }
    }
  }

  void update(float t, float dt, bool init) {
    vec3 x = Ssbo_x;
    vec3 v = Ssbo_v;
    vec3 w = Ssbo_w;
    mat3 A = Ssbo_A;
    vec3 g = U_gravity * OZN.yzy;
    float rho = 10.0;
    vec3 size = vec3(U_size_x, U_size_y, U_size_z);
    float m = rho * size.x * size.y * size.z;
    vec3 I = inertiaBox(rho, size);
    float e = 0.8;
    // [ debug collision reaction ]
    // float e = 1.0;

    // [ Algorithm ]
    // 0. update v, w by external force/torque (Newton-Euler equation)
    // 1. update x, A by v, w
    // 2. collect proximities (i.e. collisions and contacts)
    // 3. solve collision reaction and update v, w
    // 4. solve contact correction for v, w and update x, A

    // 0.
    {
      vec3 f_ext = m * g;
      vec3 tq_ext = OZN.yyy;
      float kDumpV = 0.0;
      float kDumpW = 0.2; // TODO: probably it depends on inertia or geometry ?
      vec3 f = f_ext - kDumpV * v;
      vec3 tq = tq_ext - kDumpW * A * w;
      v += dt * f / m;
      w += dt * (1.0 / I) * (inverse(A) * tq - cross(w, I * w));
    }

    // 1.
    {
      x += dt * v;
      A = A * T_axisAngle(normalize(w), dt * length(w));
    }

    // 2.
    int num_hits;
    vec3 hits[8]; // in body frame
    collectBoxProximities(x, size, A, num_hits, hits);

    // 3.
    vec3 collision_v = v;
    vec3 collision_w = w;
    mat3 I_A = A * diag(I) * inverse(A);
    vec3 n = OZN.yxy;
    for (int i = 0; i < num_hits; i++) {
      // [debug] without collision reaction
      // break;
      vec3 r = hits[i];
      vec3 p = x + A * r;
      vec3 v_p = v + A * cross(w, r);
      // [debug] use same v, w for all reaction (cf. [4 corners bounce] example below)
      // vec3 v_p = collision_v + A * cross(collision_w, r);
      float g = dot(n, p);
      float dt_g = dot(n, v_p);

      if (g >= 0.0) { continue; }
      // TODO:
      // Probably we shouldn't filter like this since it doesn't work for faster object.
      // By continuous collision checking, we can handle reaction with more accurate point velocity.
      if (dt_g >= -0.05) { continue; }

      // collision with infinite mass ground
      vec3 Ar = A * r;
      float jj =
          - (1.0 + e) * dot(n, v_p) /
            ((1.0 / m) + dot(n, cross(inverse(I_A) * cross(Ar, n), Ar)));
      vec3 j = jj * n;

      v += j / m;
      w += (1.0 / I) * (inverse(A) * cross(Ar, j));
    }

    // 4. velocity-based projection of contact constraints
    // TODO: write down proof
    mat3 Mv = mat3(m);
    mat3 Mw = diag(sqrt(I));
    int kNumIter = 4;
    for (int iter = 0; iter < kNumIter; iter++) {
      // [debug] without contact constraint
      // break;
      for (int i = 0; i < num_hits; i++) {
        vec3 r = hits[i];
        vec3 p = x + A * r;
        vec3 v_p = v + A * cross(w, r);
        float g = dot(n, p);
        float dt_g = dot(n, v_p);

        if (g >= 0.0) { continue; }
        if (dt_g >= 0.0) { continue; }

        vec3 dv_g = dt * n;
        vec3 dw_g = dt * cross(r, inverse(A) * n);

        float q = dot(dv_g, Mv * dv_g) + dot(dw_g, Mv * dw_g);
        vec3 dv = (-g / q) * dv_g;
        vec3 dw = (-g / q) * dw_g;

        // velocity correction
        v += dv;
        w += dw;

        // corresponding position correction
        x += dt * dv;
        A = A * T_axisAngle(normalize(dw), dt * length(dw));
      }
    }


    // initial values
    if (init) {
      // [ 4 corners on the ground ]
      // x = vec3(0.0, 0.5, 0.0);
      // v = vec3(0.0, 0.0, 0.0);
      // w = vec3(0.0, 0.0, 0.0) * 2.0 * M_PI;
      // A = T_rotate3(vec3(0.0, 0.0, 0.0) * M_PI);

      // [ 4 corners bounce ]
      // x = vec3(0.0, 2.0, 0.0);
      // v = vec3(0.0,-2.0, 0.0);
      // w = vec3(0.0, 0.0, 0.0) * 2.0 * M_PI;
      // A = T_rotate3(vec3(0.0, 0.0, 0.0) * M_PI);

      // [ 2 corners on the ground (perfect) ]
      // x = vec3(0.0, 0.707, 0.0);
      // v = vec3(0.0, 0.0, 0.0);
      // w = vec3(0.0, 0.0, 0.0) * 2.0 * M_PI;
      // A = T_rotate3(vec3(0.25, 0.0, 0.0) * M_PI);

      // [ 2 corners on the ground (not perfect) ]
      // x = vec3(0.0, 0.707, 0.0);
      // v = vec3(0.0, 0.0, 0.0);
      // w = vec3(0.0, 0.0, 0.0) * 2.0 * M_PI;
      // A = T_rotate3(vec3(0.24, 0.0, 0.0) * M_PI);

      // [ 2 corners bounce ]
      // x = vec3(0.0, 4.0, 0.0);
      // v = vec3(0.0, 0.0, 0.0);
      // w = vec3(0.0, 0.0, 0.0) * 2.0 * M_PI;
      // A = T_rotate3(vec3(0.25, 0.0, 0.0) * M_PI);

      // [ 1 corner on the ground ]
      // x = vec3(0.0, 0.88, 0.0);
      // v = vec3(0.0, 0.0, 0.0);
      // w = vec3(0.0, 0.0, 0.0) * 2.0 * M_PI;
      // A = T_rotate3(vec3(0.25, 0.0, 0.19) * M_PI);

      // [ 1 corner bounce ]
      // x = vec3(0.0, 1.88, 0.0);
      // v = vec3(0.0, 0.0, 0.0);
      // w = vec3(0.0, 0.0, 0.0) * 2.0 * M_PI;
      // A = T_rotate3(vec3(0.25, 0.0, 0.19) * M_PI);

      // [ Example ]
      x = vec3(0.0, 3.0, 0.0);
      v = vec3(0.0,-2.0, 0.0);
      w = vec3(0.0, 1.0, 0.0) * 2.0 * M_PI;
      A = T_rotate3(vec3(0.2, 0.0, 0.0) * M_PI);
    }
    Ssbo_x = x;
    Ssbo_v = v;
    Ssbo_w = w;
    Ssbo_A = A;
  }

  void mainCompute(/*unused*/ uvec3 comp_coord, uvec3 comp_local_coord) {
    float kTimeScale = 1.0;
    float t = Ssbo_last_time;
    float dt = kTimeScale * iTime - t;
    bool init = iFrame == 0;

    // TODO:
    // for large time step, collision reaction triggers even for static box on the ground.
    // (it should be solved by continuous collision checking. cf. dt_g >= -delta)
    // int kNumSubsteps = 1;
    int kNumSubsteps = 4;
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
    p = Ssbo_A * (scale * p) + Ssbo_x;
    n = Ssbo_A * n;

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
    p = Ssbo_A * p + Ssbo_x;

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
