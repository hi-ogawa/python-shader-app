//
// RasterscriptPlugin geometry shader test
// - [x] wire frame shading
// - [x] line anti-aliasing
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: size
      size: 1024
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex01 as ex01
        RELOAD_REC(ex01)
        RESULT = ex01.make_coordinate_grids(axes=[0, 2], grids=[1], bound=8)
      primitive: GL_LINES
      blend: true
      # capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertexLineAA
      geometry_shader: mainGeometryLineAA
      fragment_shader: mainFragmentLineAA
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 4) * 4)"
        Vertex_color:    "(gl.GL_FLOAT, 3 * 4, 4, (3 + 4) * 4)"
  - type: rasterscript
    params:
      exec: |
        import misc.mesh.src.ex00 as ex00
        RESULT = ex00.example('hedron20', num_subdiv=0, smooth=False)
      primitive: GL_TRIANGLES
      capabilities: [GL_DEPTH_TEST]
      vertex_shader: mainVertexWireframe
      geometry_shader: mainGeometryWireframe
      fragment_shader: mainFragmentWireframe
      vertex_attributes:
        Vertex_position: "(gl.GL_FLOAT, 0 * 4, 3, (3 + 3) * 4)"
        Vertex_normal:   "(gl.GL_FLOAT, 3 * 4, 3, (3 + 3) * 4)"
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


//
// Utilities
//

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/ui_v0.glsl"
#include "utils/brdf_v0.glsl"
#include "utils/hash_v0.glsl"
#include "utils/sampling_v0.glsl"

const vec3 OZN = vec3(1.0, 0.0, -1.0);

// camera
const float kYfov = 39.0 * M_PI / 180.0;
const vec3  kCameraP = vec3(2.0, 1.5, 4.0) * 2.0;
const vec3  kLookatP = vec3(0.0);

mat4 getVertexTransform(vec2 resolution) {
  mat4 view_xform = T_perspective(kYfov, resolution.x / resolution.y, 1e-3, 1e3);
  return view_xform * inverse(Ssbo_camera_xform);
}

//
// Programs
//

#ifdef COMPILE_mainVertexWireframe
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec3 Vertex_normal;
  out VertexInterface {
    vec3 position;
    vec3 normal;
  } Vertex;

  void main() {
    Vertex.position = Vertex_position;
    Vertex.normal = Vertex_normal;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(Vertex.position, 1.0);
  }
#endif

#ifdef COMPILE_mainGeometryWireframe
  layout(triangles) in;
  layout(triangle_strip, max_vertices = 3) out;
  in VertexInterface {
    vec3 position;
    vec3 normal;
  } Vertex_in[];
  out vec3 Interp_position;
  out vec3 Interp_normal;
  out vec2 Interp_uv;

  void main() {
    for (int i = 0; i < 3; i++) {
      Interp_position = Vertex_in[i].position;
      Interp_normal = Vertex_in[i].normal;
      gl_Position = gl_in[i].gl_Position;
      Interp_uv = i == 0 ? vec2(0.0, 0.0) :
                  i == 1 ? vec2(1.0, 0.0) :
                           vec2(0.0, 1.0) ;
      EmitVertex();
    }
    EndPrimitive();
  }
#endif

#ifdef COMPILE_mainFragmentWireframe
  uniform vec3 iResolution;
  in vec3 Interp_normal;
  in vec3 Interp_position;
  in vec2 Interp_uv;
  layout (location = 0) out vec4 Fragment_color;

  void main() {
    // TODO: antialias
    vec2 uv = Interp_uv;
    float d = min(min(uv.x, uv.y), 1.0 - (uv.x + uv.y));
    float fac = 1.0 - smoothstep(0.0, 2.0 * fwidth(d), d);
    vec3 color = 0.5 + 0.5 * Interp_normal;
    color = mix(color, vec3(0.9), fac);
    Fragment_color = vec4(color, 1.0);
  }
#endif


#ifdef COMPILE_mainVertexLineAA
  uniform vec3 iResolution;
  layout (location = 0) in vec3 Vertex_position;
  layout (location = 1) in vec4 Vertex_color;
  out VertexInterface {
    vec4 color;
  } Vertex;

  void main() {
    Vertex.color = Vertex_color;

    mat4 xform = getVertexTransform(iResolution.xy);
    gl_Position = xform * vec4(Vertex_position, 1.0);
  }
#endif

#ifdef COMPILE_mainGeometryLineAA
  uniform vec3 iResolution;
  layout(lines) in;
  layout(triangle_strip, max_vertices = 6) out;
  in VertexInterface {
    vec4 color;
  } Vertex_in[];
  out noperspective vec4 Interp_color;

  void getOrthgonals(vec4 p0, vec4 p1, out vec4 v0, out vec4 v1) {
    // Goal is to obtain v0 such that.
    //  1.  F(p0 + v0) - F(p0)  _|_ u
    //  2. |F(p0 + v0) - F(p0)|  = 1
    //  where
    //    F: R^3       -> R^2  (projection to window space)
    //      (x, y, z)    (W/2 * x/z,  H/2 * y/z)
    //    and
    //    u = F(p1) - F(p0)
    //
    //  NOTE:
    //  - F is non-linear so its jacobian J0, J1 is computed on each point p0 and p1 separately.
    //  - Use F(p0 + v0) - F(p0) \similar J0 (v0)
    //
    //  TODO:
    //  - Probably this argument breaks down when z < 0 ?
    //

    vec2 s = iResolution.xy / 2.0; // window space scale
    vec2 q0 = s * (p0.xy / p0.w);
    vec2 q1 = s * (p1.xy / p1.w);
    vec2 u = q1 - q0;

    mat3x2 J0 = mat3x2(
      vec2(s.x / p0.w,        0.0),
      vec2(       0.0, s.y / p0.w),
      - s * p0.xy / pow2(p0.w)
    );
    mat3x2 J1 = mat3x2(
      vec2(s.x / p1.w,        0.0),
      vec2(       0.0, s.y / p1.w),
      - s * p1.xy / pow2(p1.w)
    );

    v0.z = 0.0;
    v1.z = 0.0;
    v0.xyw = cross(vec3(0.0, 0.0, 1.0), transpose(J0) * u);
    v1.xyw = cross(vec3(0.0, 0.0, 1.0), transpose(J1) * u);
    v0 /= length(J0 * v0.xyw);
    v1 /= length(J1 * v1.xyw);
    v0 *= sign(p0.w);
    v1 *= sign(p1.w);
  }

  void main() {
    // TODO: get color right (blending, z-order, interpolation)
    vec4 c = Vertex_in[0].color;
    c = vec4(c.xyz * c.w, 1.0);  // premultiply alpha
    vec4 c_blur = c * OZN.xxxy;

    vec4 p0 = gl_in[0].gl_Position;
    vec4 p1 = gl_in[1].gl_Position;
    vec4 v0, v1;
    getOrthgonals(p0, p1, /*out*/ v0, v1);
    v0 *= 2.0;
    v1 *= 2.0;

    // [debug] pixel width
    // v0 *= 50.0;
    // v1 *= 50.0;

    Interp_color = c_blur;
    gl_Position = p0 + v0;
    EmitVertex();

    Interp_color = c_blur;
    gl_Position = p1 + v1;
    EmitVertex();

    Interp_color = c;
    gl_Position = p0;
    EmitVertex();

    Interp_color = c;
    gl_Position = p1;
    EmitVertex();

    Interp_color = c_blur;
    gl_Position = p0 - v0;
    EmitVertex();

    Interp_color = c_blur;
    gl_Position = p1 - v1;
    EmitVertex();

    EndPrimitive();
  }
#endif

#ifdef COMPILE_mainFragmentLineAA
  in noperspective vec4 Interp_color;
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
