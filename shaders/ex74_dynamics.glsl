//
// Visualize ODE (Van der Pol oscillator)
//
// - integral curve of initial value
// - integral curve as points with color gradient by time
// - integral curves from multiple initial values
//

/*
// length of trajectory
%%EXEC: os.environ['N1'] = '16'%%

// number of trajectories
%%EXEC: os.environ['N2'] = '64'%%
*/

/*
%%config-start%%
plugins:
  # [ Buffer for state ]
  - type: ssbo
    params: { binding: 1, type: size, size: 1024 }
  - type: ssbo
    params: { binding: 2, type: size, size: %%EVAL: %%ENV:N1:%% * %%ENV:N2:%% * 4 * 4%% }

  # [ points ]
  - type: rasterscript
    params:
      exec: RESULT = [bytes(), bytes(4)]
      instance_count: %%EVAL: %%ENV:N1:%% * %%ENV:N2:%% %%
      primitive: GL_POINTS
      capabilities: [GL_DEPTH_TEST, GL_PROGRAM_POINT_SIZE]
      blend: true
      vertex_shader: mainVertexDisk
      fragment_shader: mainFragmentDisk
      vertex_attributes: {}

  # [ Coordinate grid ]
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RESULT = ex01.make_coordinate_grids(axes=[0, 1, 2], grids=[2])
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
    global_size: [%%ENV:N2:%%, 1, 1]
    samplers: []

offscreen_option:
  fps: 60
  num_frames: 24
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

struct State {
  float x;
  float v;
};

layout (std140, binding = 1) buffer Ssbo1 {
  float Ssbo_last_time;
  int Ssbo_time_idx;
};

layout (std140, binding = 2) buffer Ssbo2 {
  State Ssbo_states[];
};

//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/ui_v0.glsl"
#include "utils/misc_v0.glsl"
#include "utils/hash_v0.glsl"

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(0.0, 0.0, 1.0) * 12.0;
const vec3  kLookatP = vec3(0.0);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

const ivec2 kSize = ivec2(%%ENV:N1:%%, %%ENV:N2:%%);

int toIndex(ivec2 p, ivec2 size) {
  return size.x * p.y + p.x;
}

ivec2 fromIndex(int idx, ivec2 size) {
  int x = idx % size.x;
  int y = idx / size.x;
  return ivec2(x, y);
}

#ifdef COMPILE_mainCompute
  uniform float U_mu = 1.0;

  vec2 f(float t, vec2 xv) {
    float x = xv[0];
    float v = xv[1];
    float dx = v;
    float dv = - x - U_mu * (pow2(x) - 1) * v;
    return vec2(dx, dv);
  }

  // Explicit Runge-Kutta 4th order
  vec2 runge_kutta(float t, vec2 x, float dt) {
    vec2 k1 = f(t           , x                );
    vec2 k2 = f(t + 1./2. * dt, x + 1./2. * dt * k1);
    vec2 k3 = f(t + 1./2. * dt, x + 1./2. * dt * k2);
    vec2 k4 = f(t + 1.    * dt, x + 1.    * dt * k3);
    return x + dt * (1./6. * k1 + 2./6. * k2 + 2./6. * k3 + 1./6. * k4);
  }

  State update(State state, float t, float dt, bool init, float seed) {
    vec2 xv = vec2(state.x, state.v);
    xv = runge_kutta(t, xv, dt);
    if (init) {
      vec2 uv;
      uv = Misc_halton2D(int(seed));
      xv = (uv * 2.0 - 1.0) * 3.0;
    }
    state = State(xv[0], xv[1]);
    return state;
  }

  void mainCompute(/*unused*/ uvec3 comp_coord, uvec3 comp_local_coord) {
    float t = Ssbo_last_time;
    float dt = iTime - t;
    bool init = iFrame == 0;

    ivec2 coord = ivec2(Ssbo_time_idx, gl_GlobalInvocationID.x);
    State state = Ssbo_states[toIndex(coord, kSize)];
    state = update(state, t, dt, init, float(coord.y));
    Ssbo_states[toIndex((coord + ivec2(1.0, 0.0)) % kSize, kSize)] = state;

    if (gl_GlobalInvocationID.x == 0) {
      Ssbo_last_time = iTime;
      Ssbo_time_idx = (Ssbo_time_idx + 1) % kSize.x;
    }
  }
#endif


#ifdef COMPILE_mainVertexDisk
  uniform vec3 iResolution;
  out vec3 Interp_position;
  out vec3 Interp_color;

  void main() {
    ivec2 coord = fromIndex(gl_InstanceID, kSize);
    vec3 color = Misc_hue(float(coord.x) / kSize.x * 5.0 / 6.0);
    coord.x = (Ssbo_time_idx - coord.x + kSize.x) % kSize.x;
    State state = Ssbo_states[toIndex(coord, kSize)];

    vec3 p = vec3(state.x, state.v, 0.0);
    mat4 xform = getVertexTransform(iResolution.xy);

    gl_PointSize = 3.0;
    gl_Position = xform * vec4(p, 1.0);
    Interp_position = p;
    Interp_color = color;
  }
#endif

#ifdef COMPILE_mainFragmentDisk
  uniform vec3 iResolution;
  in vec3 Interp_position;
  in vec3 Interp_color;
  in flat uint Interp_instanceId;
  in flat ivec2 Interp_idx;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    float fac = 1.0 - smoothstep(0.3, 0.7, length(gl_PointCoord - 0.5));
    Fragment_color = vec4(Interp_color, fac);
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
