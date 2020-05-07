//
// Tiling hyperbolic plane by Mobius triangle (p, q, 2)
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

  # [ Image viewer UI ]
  - type: ssbo
    params: { binding: 1, type: size, size: 1024 }
  - type: raster
    params: { primitive: GL_POINTS, count: 1, vertex_shader: mainVertexUI, fragment_shader: mainFragmentDiscard }

  # [ Variable ]
  - type: uniformlist
    params:
      name: ['U_scale', 'U_rotate', 'U_num_iter', 'U_mobius_p', 'U_mobius_q']
      default: [   2, 0,  64,  7,  3]
      min:     [-32, -2,   0,  4,  2]
      max:     [+32, +2, 128, 10, 10]

samplers: []
programs: []
offscreen_option: { fps: 60, num_frames: 2 }
%%config-end%%
*/

// ssbo: ui state
layout (std140, binding = 1) buffer Ssbo1 {
  bool Ssbo_mouse_down;
  vec2 Ssbo_mouse_down_p;
  vec2 Ssbo_mouse_click_p;
  mat3 Ssbo_inv_view_xform;
};

#include "utils/math_v0.glsl"
#include "utils/transform_v0.glsl"
#include "utils/misc_v0.glsl"
#include "utils/ui_v0.glsl"

#ifdef COMPILE_mainV
  layout (location = 0) in vec2 VertexIn_position;
  void main() {
    gl_Position = vec4(VertexIn_position, 0, 1.0);
  }
#endif

#ifdef COMPILE_mainF
  uniform vec3 iResolution;
  uniform float U_AA = 1.5;
  uniform float U_scale = 2.0;
  uniform float U_rotate = 0.0;
  uniform float U_num_iter = 64.0;
  uniform float U_mobius_p = 7.0;
  uniform float U_mobius_q = 3.0;
  layout (location = 0) out vec4 FragmentOut_color;

  vec3 kColor1 = vec3(1.0, 0.5, 0.0);
  vec3 kColor2 = vec3(0.0, 1.0, 0.5);

  vec3 mixColor(vec3 c1, vec3 c2, float t) {
    c1 = pow(c1, vec3(2.2));
    c2 = pow(c2, vec3(2.2));
    vec3 c;
    c = mix(c1, c2, t);
    c = pow(c, vec3(1.0/2.2));
    return c;
  }

  vec4 renderPixel(vec2 frag_coord) {
    // Pattern break around 2^12 and 2^{-12}
    mat3 inv_view_xform =  inverse(mat3(mat2(pow(2.0, U_scale)))) * Ssbo_inv_view_xform;
    mat3 view_xform = inverse(inv_view_xform);
    float AA = U_AA;
    int mobius_p = int(U_mobius_p);
    int mobius_q = int(U_mobius_q);
    vec3 color = vec3(0.0);

    vec2 p = vec2(inv_view_xform * vec3(frag_coord, 1.0));
    mat2 jacobian = mat2(1.0);
    mat2 jacobian_init = mat2(1.0);


    // Initial "mobius rotation"
    // z |-> (cos(t/2) z - sin(t/2)) / (sin(t/2) z + cos(t/2))
    // NOTE:
    // - this is the stabilizer of "i" which is isomorphic to S^1
    // - this corresponds to rotation in S^3 via stereographic projection.
    {
      float t = - U_rotate * M_PI;
      float c = cos(t / 2.0);
      float s = sin(t / 2.0);
      vec2 az_b = c * p - s * OZN.xy;
      vec2 cz_d = s * p + c * OZN.xy;
      vec2 cz_d_inv = c_inv(cz_d);
      p = c_mul(az_b) * cz_d_inv;
      jacobian = pow2(c_mul(cz_d_inv)) * jacobian;
      jacobian_init = jacobian;
    }

    // Fundamental triangle is given by
    // (1) i y with y > 0
    // (2) exp(i t)
    // (3) - mu + r exp(i t)
    float fund_mu;
    float fund_r;

    // For (3), we solve this (TODO: write down proof)
    //   known: phi1, phi2
    //   var:  r, mu, phi3, phi4
    //   eq:
    //     1: mu / r = cos(phi1)
    //     2: phi2 = phi3 - phi4
    //     3: r sin(phi4) = sin(phi3)
    //     4: r cos(phi4) = mu + cos(phi3)
    //
    // It turns out it's easy to compute this in disk model and use iso (z - i) / (z + i) (Cayley transform).
    // (cf. mla's `solve` in https://www.shadertoy.com/view/Wdjyzm)
    //

    // Solve it in half plane
    {
      float phi1 = M_PI / float(mobius_p);
      float phi2 = M_PI / float(mobius_q);
      float sin_phi3 = sin(phi2) / cos(phi1);
      float cos_phi3 = sqrt(1 - dot2(sin_phi3));
      fund_r = sin_phi3 / (sin_phi3 * cos(phi2) - cos_phi3 * sin(phi2));
      fund_mu = fund_r * cos(phi1);
    }

    // Solve it in disk model
    //   known: phi1, phi2
    //   var: x, y, r
    //   eq:
    //     1: x = + r sin(phi2)
    //     2: y = - r cos(phi1)
    //     3: r^2 + 1 = |(x, y)|^2
    // NOTE:
    // - Mobius transform (Cayley transform) doesn't preserve Euclidian center/radius
    //   so, we can't directly use them. What we can use is the intersections of hyperbolic lines.
    // - Inverse of (z - i) / (z + i) is (w + 1) / (i w - i)
    //
    {
      // TODO: something seems wrong
      float phi1 = M_PI / float(mobius_p);
      float phi2 = M_PI / float(mobius_q);
      float r = sqrt(1.0 / (pow2(sin(phi2)) + pow2(cos(phi1)) - 1.0));
      vec2 c = r * vec2(sin(phi2), - cos(phi1));

      // bringing it back to half plane still looks a bit messy though
      vec2 w1 = vec2(r * (sin(phi2) - sin(phi1)), 0.0);
      vec2 w2 = vec2(0.0, - r * (cos(phi1) - cos(phi2)));

      // TODO: these two supposed to be fundmantal triangle's vertices but it's not...
      vec2 z1 = c_mul(w1 + OZN.xy) * c_inv(c_mul(OZN.yx) * w1 - OZN.yx);
      vec2 z2 = c_mul(w2 + OZN.xy) * c_inv(c_mul(OZN.yx) * w2 - OZN.yx);

      // fund_mu = ???
      // fund_r = ???

      // float width = 4.0;
      // float ud = min(length(p - z1), length(p - z2));
      // ud *= view_xform[0][0];
      // float sd = ud - width;
      // float fac = 1.0 - smoothstep(0.0, 1.0, sd / AA + 0.5);
      // color = mixColor(color, OZN.xxx, fac);
    }

    //
    // Iterate reflection
    //
    // Hyperbolic line's (anti holomorphic) reflection is Euclidian circle's inversion
    //    m(z) = c + r^2 / (z - c)^\dag
    //   Dm(z) = ( r^2 / (z - c)^2 )^\dag
    vec2 c1 = vec2(0.0);
    float r1 = 1.0;
    vec2 c2 = vec2(- fund_mu, 0.0);
    float r2 = fund_r;

    {
      // Use different variable since we use p later
      vec2 q = p;

      int parity_2 = 0;
      int parity_q = 0;
      float success = 0.0;

      for (int i = 0; i < int(U_num_iter); i++) {
        if (q.y <= 0.0) {
          break;
        }

        float l1 = length(q - c1);
        float l2 = length(q - c2);
        if (r1 <= l1 && l2 <= r2 && 0.0 <= q.x) {
          success = 1.0;
          break;
        }

        if (r1 > l1) {
          parity_2++;
          parity_q++;
          jacobian = pow2(c_mul(c_conj(r1 * c_inv(q - c1)))) * jacobian;
          q = c1 + pow2(r1) * c_conj(c_inv(q - c1));

        } else
        if (l2 > r2) {
          parity_2++;
          jacobian = pow2(c_mul(c_conj(r2 * c_inv(q - c2)))) * jacobian;
          q = c2 + pow2(r2) * c_conj(c_inv(q - c2));

        } else

        if (0.0 > q.x) {
          parity_2++;
          jacobian = diag(vec2(-1.0, 1.0)) * jacobian;
          q = diag(vec2(-1.0, 1.0)) * q;
        }
      }

      float parity = sign(float(parity_2 % 2) - 0.5); // {-1, 1}

      if (success != 1.0) {
        color += vec3(0.1, 0.2, 0.3);
      }

      if (success == 1.0) {
        float ud0 = abs(q.x);
        float ud1 = abs(length(q - c1) - r1);
        float ud2 = abs(length(q - c2) - r2);

        vec2 g0 = vec2(1.0, 0.0);
        vec2 g1 = normalize(q - c1);
        vec2 g2 = normalize(q - c2);

        float ud = 1e7;
        ud = min(ud, ud0 / length(g0 * jacobian * mat2(inv_view_xform)));
        ud = min(ud, ud1 / length(g1 * jacobian * mat2(inv_view_xform)));
        ud = min(ud, ud2 / length(g2 * jacobian * mat2(inv_view_xform)));

        float sd = - parity * ud;
        float fac = 1.0 - smoothstep(0.0, 1.0, sd / AA + 0.5);
        color += mixColor(kColor1, kColor2, fac);

        // TODO: different color for neighboring p-gons
        // color = Misc_hue(float(parity_q % mobius_q) / float(mobius_q));

        {
          float width = 1.0;
          float ud = ud1 / length(g1 * jacobian * mat2(inv_view_xform));
          float sd = ud - width;
          float fac = 1.0 - smoothstep(0.0, 1.0, sd / AA + 0.5);
          color = mixColor(color, OZN.xxx * 0.2, fac);
        }
      }
    }

    // Fundamental domain boundary
    {
      float ud0 = abs(p.x);
      float ud1 = abs(length(p - c1) - r1);
      float ud2 = abs(length(p - c2) - r2);

      vec2 g0 = vec2(1.0, 0.0);
      vec2 g1 = normalize(p - c1);
      vec2 g2 = normalize(p - c2);

      // edge 0
      {
        float width = 3.0;
        float ud = ud0 / length(g0 * jacobian_init * mat2(inv_view_xform));
        float sd = ud - width / 2.0;
        float fac = 1.0 - smoothstep(0.0, 1.0, sd / AA + 0.5);
        color = mixColor(color, vec3(0.0, 0.0, 1.0), fac);
      }

      // edge 1
      {
        float width = 3.0;
        float ud = ud1 / length(g1 * jacobian_init * mat2(inv_view_xform));
        float sd = ud - width / 2.0;
        float fac = 1.0 - smoothstep(0.0, 1.0, sd / AA + 0.5);
        color = mixColor(color, OZN.xxx, fac);
      }

      // edge 2
      {
        float width = 3.0;
        float ud = ud2 / length(g2 * jacobian_init * mat2(inv_view_xform));
        float sd = ud - width / 2.0;
        float fac = 1.0 - smoothstep(0.0, 1.0, sd / AA + 0.5);
        color = mixColor(color, vec3(1.0, 0.2, 0.2), fac);
      }

    }

    return vec4(color, 1.0);
  }

  void main() {
    FragmentOut_color = renderPixel(gl_FragCoord.xy);
  }
#endif


//
// Program: UI
//

#ifdef COMPILE_mainVertexUI
  uniform vec3 iResolution;
  uniform vec4 iMouse;
  uniform uint iKeyModifiers;
  uniform int iFrame;

  void main() {
    if (iFrame == 0) {
      float height = 4.0;
      Ssbo_inv_view_xform =
          T_translate2(OZN.yx * height)
          * T_invView(2.0 * atan(height), iResolution.xy);
    }
    UI_interactInvViewXform(iResolution.xy, iMouse, iKeyModifiers,
        Ssbo_mouse_down, Ssbo_mouse_down_p, Ssbo_mouse_click_p, Ssbo_inv_view_xform);
  }
#endif

#ifdef COMPILE_mainFragmentDiscard
  layout (location = 0) out vec4 Fragment_color;
  void main() {
    discard;
  }
#endif
