//
// Stereographic projection, which demonstrates
//
//     S^2 -(SP)-> C
//  Rot |          | Mobius[Rot]
//     S^2 -(SP)-> C
//

/*
%%config-start%%
plugins:
  # [ Ground ]
  - type: rasterscript
    params:
      exec: |
        import numpy as np
        from misc.mesh.src import data, utils
        p_vs = np.array([[0, 0, -1], [0, 0, 1], [1, 0, 1], [0, 0, 1]] , np.float32)
        p_vs *= 128
        faces = np.array([[0, 1, 2], [0, 2, 3]], np.uint32)
        verts, faces = utils.finalize(p_vs, faces, smooth=False)
        RESULT = bytes(verts), bytes(faces)
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertex
      fragment_shader: mainFragmentGround
      vertex_attributes:
        VertexIn_position: "(gl.GL_FLOAT, 0 * 4, 3, 6 * 4)"
        VertexIn_normal:   "(gl.GL_FLOAT, 3 * 4, 3, 6 * 4)"

  # [ Geometry ]
  - type: rasterscript
    params:
      exec: |
        from misc.mesh.src import data, utils
        p_vs, faces = data.hedron20()
        for _ in range(3):
          p_vs, faces = utils.subdiv_triforce(p_vs, faces)
        p_vs = utils.normalize(p_vs)
        verts, faces = utils.finalize(p_vs, faces, smooth=True)
        RESULT = bytes(verts), bytes(faces)
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      blend: true
      vertex_shader: mainVertex
      fragment_shader: mainFragmentSphere
      vertex_attributes:
        VertexIn_position: "(gl.GL_FLOAT, 0 * 4, 3, 6 * 4)"
        VertexIn_normal:   "(gl.GL_FLOAT, 3 * 4, 3, 6 * 4)"

  # [ UI state management ]
  - type: ssbo
    params: { binding: 0, type: size, size: 1024 }
  - type: raster
    params: { primitive: GL_POINTS, count: 1, vertex_shader: mainVertexUI, fragment_shader: mainFragmentDiscard }

  # [ Variable ]
  - type: uniformlist
    params:
      name: ['U_rotate', 'U_use_mobius']
      default: [ 0, 1]
      min:     [-2, 0]
      max:     [+2, 2]

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
const vec3  kCameraP = vec3(-3.0, 2.0, 1.5) * 1.0;
const vec3  kLookatP = vec3(1.0, 0.0, 0.0);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

vec3 kColor1 = vec3(1.0, 0.5, 0.0);
vec3 kColor2 = vec3(0.0, 1.0, 0.5);
uniform float U_rotate = 0.0;
uniform float U_use_mobius = 1.0;

vec3 mixColor(vec3 c1, vec3 c2, float t) {
  c1 = pow(c1, vec3(2.2));
  c2 = pow(c2, vec3(2.2));
  vec3 c;
  c = mix(c1, c2, t);
  c = pow(c, vec3(1.0/2.2));
  return c;
}

void cartesianToSphericalWithJacobian(
    vec3 p, out vec3 rtp, out mat3 jacobian) {
  rtp = T_cartesianToSpherical(p);
  float r = rtp.x;
  float t1 = rtp.y;
  float t2 = rtp.z;
  jacobian[0] = normalize(p);
  jacobian[1] = r * vec3(
      cos(t1) * cos(t2),
      cos(t1) * sin(t2),
      - sin(t1));
  jacobian[2] = r * sin(t1) * vec3(
      - sin(t2),
      cos(t2),
      0.0);
  jacobian = inverse(jacobian);
}

void stereographicInvWithJacobian(
    vec2 p, out vec3 q, out mat2x3 jacobian) {
  float p2 = dot2(p);
  q = vec3(p2 - 1, 2.0 * p) / (p2 + 1);
  // J = 1 / (|y|^2 + 1)^2
  //   \matrix
  //     4 y^T
  //     2 ( (|y|^2 + 1) I - 2 y y^T )
  mat2 tmp1 = 2.0 * ((p2 + 1) * mat2(1.0) - 2.0 * outer2(p));
  mat3x2 tmp2;
  tmp2[0] = 4.0 * p;
  tmp2[1] = tmp1[0];
  tmp2[2] = tmp1[1];
  jacobian = transpose(tmp2) / pow2(p2 + 1.0);
}


float sdfSpherePattern(vec3 p, mat2x3 jacobian) {
  float theta;
  float phi;
  {
    vec3 rtp;
    mat3 tmp_jacobian;
    cartesianToSphericalWithJacobian(p, rtp, tmp_jacobian);
    theta = rtp.y;
    phi = rtp.z;
    jacobian = tmp_jacobian * jacobian;
  }
  int parity = 0;
  float ud = 1e7;

  // grid along phi
  {
    float k = M_PI / 6.0;
    float ud1 = k * min(fract(phi / k), 1.0 - fract(phi / k));
    vec3 grad = vec3(0.0, 0.0, 1.0);
    ud1 /= length(grad * jacobian);

    ud = min(ud, ud1);
    parity += int(floor(phi / k));
  }

  // grid along theta (equi-distance as hyperbolic half plane)
  {
    float a = 0.5 * M_PI - theta;  // half-plane angle
    float f = - log(tan(a / 2.0)); // half-plane arc distance
    float grad_f = - 1.0 / (2.0 * sin(a / 2.0));

    float k = 0.3;
    float ud2 = k * min(fract(f / k), 1.0 - fract(f / k));
    vec3 grad = vec3(0.0, grad_f, 0.0);
    ud2 /= length(grad * jacobian);

    ud = min(ud, ud2);
    parity += int(floor(f / k));
  }

  float sd = sign((parity % 2) - 0.5) * ud;
  return sd;
}


#ifdef COMPILE_mainVertex
  uniform vec3 iResolution;
  layout (location = 0) in vec3 VertexIn_position;
  layout (location = 1) in vec3 VertexIn_normal;
  out vec3 VertexOut_position;
  out vec3 VertexOut_normal;
  out vec4 VertexOut_color;

  void main() {
    vec3 p = VertexIn_position;
    vec3 n = VertexIn_normal;
    vec4 color = vec4(1.0);

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(p, 1.0);
    VertexOut_position = p;
    VertexOut_normal = n;
    VertexOut_color = color;
  }
#endif


#ifdef COMPILE_mainFragmentSphere
  in vec3 VertexOut_normal;
  in vec3 VertexOut_position;
  in vec4 VertexOut_color;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    float AA = 1.5;
    vec3 p = VertexOut_position;
    p = p.yzx; // use different frame so that `cartesianToSpherical` becomes trivial
    if (p.z <= 0.05) { discard; return; }

    mat2x3 inv_view_xform = mat2x3(dFdx(p), dFdy(p)); // derivative d(scene)/d(window)
    mat2x3 jacobian = inv_view_xform;

    {
      mat3 xform = T_rotate3(OZN.yyx * M_PI * - U_rotate);
      p = xform * p;
      jacobian = xform * jacobian;
    }

    float sd = sdfSpherePattern(p, jacobian);
    float fac = 1.0 - smoothstep(0.0, 1.0, sd / AA + 0.5);
    Fragment_color = vec4(OZN.xxx, fac * 0.8);
  }
#endif


#ifdef COMPILE_mainFragmentGround
  in vec3 VertexOut_normal;
  in vec3 VertexOut_position;
  in vec4 VertexOut_color;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    float AA = 1.5;
    bool use_mobius = 1.0 <= U_use_mobius;

    vec3 p = VertexOut_position;
    p = p.yzx;

    mat2 inv_view_xform = mat2x2(dFdx(p.yz), dFdy(p.yz)); // derivative d(scene)/d(window)
    mat2 jacobian2 = inv_view_xform;
    mat2x3 jacobian23;

    // these two transformation is equivalent

    if (use_mobius) {
      // SP^{-1} . Rot(Mobius)
      {
        // z |-> (cos(t/2) z - sin(t/2)) / (sin(t/2) z + cos(t/2))
        vec2 z = p.yz;
        float t = - U_rotate * M_PI;
        float c = cos(t / 2.0);
        float s = sin(t / 2.0);
        vec2 az_b = c * z - s * OZN.xy;
        vec2 cz_d = s * z + c * OZN.xy;
        vec2 cz_d_inv = c_inv(cz_d);
        z = c_mul(az_b) * cz_d_inv;
        p.yz = z;
        jacobian2 = pow2(c_mul(cz_d_inv)) * jacobian2;
      }
      {
        mat2x3 tmp_jacobian;
        stereographicInvWithJacobian(p.yz, p, tmp_jacobian);
        jacobian23 = tmp_jacobian * jacobian2;
      }

    } else {
      // Rot(S2) . SP^{-1}
      {
        mat2x3 tmp_jacobian;
        stereographicInvWithJacobian(p.yz, p, tmp_jacobian);
        jacobian23 = tmp_jacobian * jacobian2;
      }
      {
        mat3 xform = T_rotate3(- U_rotate * M_PI * OZN.yyx);
        p = xform * p;
        jacobian23 = xform * jacobian23;
      }
    }

    float sd = sdfSpherePattern(p, jacobian23);
    float fac = 1.0 - smoothstep(0.0, 1.0, sd / AA + 0.5);
    vec3 color = mixColor(kColor2, kColor1, fac);
    Fragment_color = vec4(color, 1.0);
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
