//
// Tiling flat 2d space
//


/*
%%config-start%%
plugins:
  # [ Quad ]
  - type: rasterscript
    params:
      exec: from misc.mesh.src import data; RESULT = list(map(bytes, data.quad()))
      primitive: GL_TRIANGLES
      vertex_shader: mainV
      fragment_shader: mainF
      vertex_attributes: { VertexIn_position: "(gl.GL_FLOAT, 0 * 4, 2, 2 * 4)" }

samplers: []
programs: []
%%config-end%%
*/

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/misc_v0.glsl"

#ifdef COMPILE_mainV
  layout (location = 0) in vec2 VertexIn_position;
  void main() {
    gl_Position = vec4(VertexIn_position, 0, 1.0);
  }
#endif

#ifdef COMPILE_mainF
  uniform vec3 iResolution;
  uniform float U_AA = 1.5;
  uniform float U_type = 2.0;
  layout (location = 0) out vec4 FragmentOut_color;

  vec3 kColor1 = vec3(1.0, 0.5, 0.0);
  vec3 kColor2 = vec3(0.0, 1.0, 0.5);

  vec3 mixColor(vec3 c1, vec3 c2, float t) {
    c1 = pow(c1, vec3(2.2));
    c2 = pow(c2, vec3(2.2));
    vec3 y = vec3(0.2126, 0.7152, 0.0722);
    vec3 c;
    c = mix(c1, c2, t);
    c = pow(c, vec3(1.0/2.2));
    return c;
  }

  float reflectWithParity(vec2 p, vec2 lp, vec2 ln, out vec2 p_out) {
    vec2 v = p - lp;
    float parity = sign(dot(v, ln));
    p_out = 0.0 < parity ? p : lp + reflect(v, ln);
    return parity;
  }

  vec2 hyperPlaneToPoint(vec2 p, vec2 hp, vec2 hn) {
    return outer2(hn) * (p - hp);
  }

  vec4 renderPixel(vec2 frag_coord, vec2 resolution) {
    mat3 invViewXform = T_invView(2.0 * atan(2.0), resolution);
    mat3 viewXform = inverse(invViewXform);
    float AA = U_AA;
    vec3 color;

    // (3, 3, 3)
    if (U_type < 1.0) {
      vec2 p = vec2(invViewXform * vec3(frag_coord, 1.0));

      // Make lattice of parallelogram
      mat2 lattice = mat2(OZN.xy, T_rotate2(+ M_PI / 3.0) * OZN.xy);
      p = lattice * fract(inverse(lattice) * p);

      // fold [0, 1]^2 into {(x, y) | x + y <= 1} with tracking parity
      float parity = 1.0;
      parity *= reflectWithParity(p, OZN.xy, T_rotate2(M_PI * 7.0 / 6.0) * OZN.xy, /*out*/ p);

      // fold further to get edge distance
      vec2 q = p;
      reflectWithParity(q, OZN.yy, T_rotate2(M_PI * 5.0 / 3.0) * OZN.xy, /*out*/ q);

      float ud_lattice = length(mat2(viewXform) * hyperPlaneToPoint(q, OZN.yy, OZN.yx));
      float ud = min(ud_lattice, length(mat2(viewXform) * hyperPlaneToPoint(p, OZN.xy, T_rotate2(M_PI / 6.0) * OZN.xy)));

      float sd = - parity * ud;
      float fac = smoothstep(0.0, 1.0, sd / AA + 0.5);
      color = mixColor(kColor1, kColor2, fac);

      {
        // Draw lattice cell edge
        float edge_width = 1.0;
        float sd = ud_lattice - edge_width;
        float fac = smoothstep(0.0, 1.0, sd / AA + 0.5);
        color = mixColor(vec3(0.5), color, fac);
      }
    } else

    // (4, 4, 2)
    if (U_type < 2.0) {
      vec2 p = vec2(invViewXform * vec3(frag_coord, 1.0));

      // Make lattice of square [0, 2]^2
      p = fract(p / 2.0) * 2.0;

      // fold [0, 1]^2 into {(x, y) | x <= y <= 0.5} with tracking reflection parity
      float parity = 1;
      parity *= reflectWithParity(p, OZN.xy, - OZN.xy, p);
      parity *= reflectWithParity(p, OZN.yx, - OZN.yx, p);
      parity *= reflectWithParity(p, OZN.yy, normalize(OZN.xz), p);

      // Distance to edge of fundamental domain (right triangle)
      float ud = 1e7;
      #define UPDATE(A1, A2) \
          ud = min(ud, length(mat2(viewXform) * hyperPlaneToPoint(p, A1, A2)))
        UPDATE(OZN.xy, OZN.xy);
        UPDATE(OZN.yy, OZN.yx);
        UPDATE(OZN.yy, normalize(OZN.xz));
      #undef UPDATE

      float sd = - parity * ud;
      float fac = smoothstep(0.0, 1.0, sd / AA + 0.5);
      color = mixColor(kColor1, kColor2, fac);

      {
        // Draw lattice cell edge
        float ud_lattice = length(mat2(viewXform) * hyperPlaneToPoint(p, OZN.yy, OZN.yx));
        float edge_width = 1.0;
        float sd = ud_lattice - edge_width;
        float fac = smoothstep(0.0, 1.0, sd / AA + 0.5);
        color = mixColor(vec3(0.5), color, fac);
      }
    } else

    // (6, 3, 2)
    if (true) {
      vec2 p = vec2(invViewXform * vec3(frag_coord, 1.0));

      // Make lattice of parallelogram
      mat2 lattice = sqrt(3.0) * mat2(
          T_rotate2(- M_PI / 6.0) * OZN.xy,
          T_rotate2(+ M_PI / 6.0) * OZN.xy);
      p = lattice * fract(inverse(lattice) * p);


      // Reflect within single lattice cell and track parity
      float parity = 1.0;
      parity *= reflectWithParity(p,       OZN.yy,                                 OZN.yx, /*out*/ p);
      parity *= reflectWithParity(p, 1.5 * OZN.xy,                               - OZN.xy, /*out*/ p);

      // Distance to lattice cell edge
      float ud_lattice = length(mat2(viewXform) * hyperPlaneToPoint(
          p, OZN.yy, T_rotate2(M_PI * 2.0 / 3.0) * OZN.xy));

      // Continue reflecting
      parity *= reflectWithParity(p,       OZN.xy, + T_rotate2(M_PI * 5.0 / 6.0) * OZN.xy, /*out*/ p);
      parity *= reflectWithParity(p,       OZN.xy, - T_rotate2(M_PI * 1.0 / 6.0) * OZN.xy, /*out*/ p);

      {
        // Distance to edge of fundamental domain (right triangle)
        float ud = 1e7;
        #define UPDATE(A1, A2) \
            ud = min(ud, length(mat2(viewXform) * hyperPlaneToPoint(p, A1, A2)))
          UPDATE(OZN.xy, T_rotate2(M_PI * 1.0 / 6.0) * OZN.xy);
          UPDATE(OZN.yy, T_rotate2(M_PI * 2.0 / 3.0) * OZN.xy);
          UPDATE(OZN.yy,                               OZN.yx);
        #undef UPDATE
        float sd = - parity * ud;
        float fac = smoothstep(0.0, 1.0, sd / AA + 0.5);
        color = mixColor(kColor1, kColor2, fac);
      }

      {
        // Distance to edge of hexagon
        float ud = length(mat2(viewXform) * hyperPlaneToPoint(
            p, OZN.xy, T_rotate2(M_PI * 1.0 / 6.0) * OZN.xy));

        float edge_width = 1.5;
        float sd = ud - edge_width;

        float fac = smoothstep(0.0, 1.0, sd / AA + 0.5);
        color = mixColor(vec3(0.3), color, fac);
      }

      {
        // Draw original lattice cell edge
        float edge_width = 1.0;
        float sd = ud_lattice - edge_width;
        float fac = smoothstep(0.0, 1.0, sd / AA + 0.5);
        color = mixColor(vec3(0.5), color, fac);
      }
    }

    return vec4(color, 1.0);
  }

  void main() {
    FragmentOut_color = renderPixel(gl_FragCoord.xy, iResolution.xy);
  }
#endif
