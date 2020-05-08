//
// Fatou/Julia set
// (Shading interior of filled julia set based on Koenigs linearized coordinate)
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

  uint Ssbo_key;
  vec2 Ssbo_c;
  vec2 Ssbo_z0;
  float Ssbo_use_logistic;
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
  layout (location = 0) out vec4 FragmentOut_color;

  vec3 mixColor(vec3 c1, vec3 c2, float t) {
    c1 = pow(c1, vec3(2.2));
    c2 = pow(c2, vec3(2.2));
    vec3 c;
    c = mix(c1, c2, t);
    c = pow(c, vec3(1.0/2.2));
    return c;
  }

  float sdToFactor(float sd, float aa_width) {
    return 1.0 - smoothstep(0.0, 1.0, sd / aa_width + 0.5);
  }

  float udToFactor(float ud, float width, float aa_width) {
    return sdToFactor(ud - width / 2.0, aa_width);
  }

  float udFromGrad(float ud, vec2 grad, mat2 dpdw) {
    return ud / length(grad * dpdw);
  }

  float scaleByGrad(float ud, vec2 grad, mat2 dpdw) {
    return ud / length(grad * dpdw);
  }

  float udLineSegmentWithGrad(vec2 p, vec2 q1, vec2 q2, out vec2 grad) {
    vec2 v = p - q1;
    float l = length(q2 - q1);
    if (l < 1e-4) { grad = normalize(p - q1); return length(p - q1); }

    vec2 n = (q2 - q1) / l;
    float t = dot(n, v);
    float tb = clamp(t, 0.0, l);
    grad = T_rotate2(0.5 * M_PI) * n;
    return distance(v, tb * n);
  }

  void coordinate2d(vec2 p, mat2 dpdw, out float sd_out, out vec3 color_out) {
    sd_out = 1e7;
    #define MERGE_SD(SD_OUT, SD, X_OUT, X) \
        if (SD < SD_OUT) { SD_OUT = SD; X_OUT = X; }

    #define XXX(UD, GRAD, WIDTH, COLOR) \
        {                                                     \
          float sd = UD / length(GRAD * dpdw) - 0.5 * WIDTH;  \
          MERGE_SD(sd_out, sd, color_out, COLOR);             \
        }
      XXX(min(fract(p.x), 1.0 - fract(p.x)), OZN.xy, 1.0, OZN.xxx * 0.5)
      XXX(min(fract(p.y), 1.0 - fract(p.y)), OZN.yx, 1.0, OZN.xxx * 0.5)
      XXX(abs(p.x),                          OZN.xy, 2.0, OZN.xyy * 0.5)
      XXX(abs(p.y),                          OZN.xy, 2.0, OZN.yxy * 0.5)

    #undef XXX
    #undef MERGE_SD
  }

  // a x (1 - x) --(holom. change.)--> z^2 - c where
  //  z = - x / a + 1 / 2
  //  c = - a (a - 2) / 4
  vec2 toLogistic(vec2 a) {
    return - c_mul(a) * (a - 2.0 * c_1) / 4.0;
  }

  vec4 renderPixel(vec2 frag_coord) {
    mat3 inv_view_xform = Ssbo_inv_view_xform;
    mat3 view_xform = inverse(inv_view_xform);

    float AA = 1.5;
    vec3 color = OZN.yyy;
    vec2 p = vec2(inv_view_xform * vec3(frag_coord, 1.0));
    vec2 c = Ssbo_c;
    bool use_logistic = bool(Ssbo_use_logistic);
    mat2 dpdw = mat2(inv_view_xform);

    // Draw coordinate grid
    {
      float sd_tmp; vec3 color_tmp;
      coordinate2d(p, mat2(inv_view_xform), sd_tmp, color_tmp);
      color = mixColor(color, color_tmp, sdToFactor(sd_tmp, AA));
    }

    // Draw Mandelbrot set
    {
      vec2 cc = !use_logistic ? p : toLogistic(p);
      vec2 z = c_0;
      int kEscapeMax = 1024;
      int escape_time = 0;
      for (; escape_time < kEscapeMax; escape_time++) {
        if (4.0 < dot2(z)) { break; }
        z = c_mul(z) * z + cc;
      }
      vec3 escape_color;
      escape_color = OZN.xxx * float(escape_time) / kEscapeMax;
      color += escape_color * 0.25;
    }

    // Draw Fatou/Julia set
    {
      // Positive root of z^2 - |c| = z
      float z_lim = 0.5 * (1.0 + sqrt(1.0 + 4.0 * length(c)));

      // Attractive fixed point and its derivative (if |c| < 1 with "logistic")
      vec2 zz = 0.5 * c;
      vec2 lam = c;

      vec2 z = p;
      vec2 cc = !use_logistic ? c : toLogistic(c);
      int kIterMax = 1024;
      int iter = 0;
      bool basin = false;
      for (; iter < kIterMax; iter++) {
        if (length(z) > z_lim + 1e-3) { break; }
        if (length(z - zz) < 1e-3) { basin = true; break; }
        z = c_mul(z) * z + cc;
      }

      vec3 koenigs_color = OZN.yyy;
      if (basin) {
        vec2 w = z - zz; // at neighborhood, Koenigs coord is already linear
        float t_w = atan(w.y, w.x);
        float t_lam = atan(lam.y, lam.x); // iterate back by multiplizer (i.e. f'(zz))
        float t = t_w - iter * t_lam;     // to obtain phase.
        float s = float(iter) * - log(length(lam)); // log of Koenigs coord amplitude
        koenigs_color = Misc_hue(t / (2.0 * M_PI));

        // [ modulate (contourline) by amplitude, which is difficult to scale ]
        // float kFac = 1.0;
        // koenigs_color *= (0.5 + 0.5 * cos(kFac * s));
      }
      color += koenigs_color * 0.8;
    }

    // Draw iteration from z0
    {
      const int kNumIter = 32;
      vec2 zs[kNumIter];
      zs[0] = Ssbo_z0;
      vec2 cc = !use_logistic ? c : toLogistic(c);
      for (int i = 1; i < kNumIter; i++) {
        vec2 z = zs[i - 1];
        zs[i] = c_mul(z) * z + cc;
      }

      for (int i = 0; i < kNumIter; i++) {
        vec2 z = zs[i];
        if (1e3 < length(z)) { break; }

        float ud = length(p - z) / length(normalize(p - z) * dpdw);
        float fac = udToFactor(ud, 4.0, AA);
        color = mixColor(color, vec3(1.0, 0.5, 0.0), fac);

        if (0 < i) {
          vec2 zz = zs[i - 1];
          vec2 grad;
          float ud = udLineSegmentWithGrad(p, zz, z, /*out*/ grad);
          float fac = udToFactor(ud / length(grad * dpdw), 1.5, AA);
          color = mixColor(color, OZN.xxx * 0.8, fac);
        }
      }
    }

    // Draw c
    {
      float ud = length(p - c) / length(normalize(p - c) * dpdw);
      float fac = udToFactor(ud, 8.0, AA);
      color = mixColor(color, OZN.yyx, fac);
    }

    // Draw fixed point (try putting z0 to repeling fixed point, whose path follows fractal pattern.)
    if (use_logistic) {
      // fixed points z = c/2 or 1 - c/2
      // with derivative f'(z) = 2 z = c or 2 - c
      vec2 zz = 0.5 * c;
      {
        float ud = length(p - zz) / length(normalize(p - zz) * dpdw);
        float fac = udToFactor(ud, 6.0, AA);
        color = mixColor(color, OZN.xxx, fac);
      }
      {
        float ud = length(p - (c_1 - zz)) / length(normalize(p - (c_1 - zz)) * dpdw);
        float fac = udToFactor(ud, 6.0, AA);
        color = mixColor(color, OZN.xxx, fac);
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
  uniform uint iKey;
  uniform uint iKeyModifiers;
  uniform int iFrame;

  void main() {
    bool mouse_action = UI_interactInvViewXform(
        iResolution.xy, iMouse, iKeyModifiers,
        Ssbo_mouse_down, Ssbo_mouse_down_p, Ssbo_mouse_click_p, Ssbo_inv_view_xform);

    // shift, control, alt
    uint kModifiers[] = uint[](
        0x02000000u, 0x04000000u, 0x08000000u);

    uint kKeyA = 0x41u;
    uint kKeyD = 0x44u;
    uint kKeyS = 0x53u;
    uint kKeyW = 0x51u;

    if (iFrame == 0) {
      vec2 center = vec2(0.0, 0.0);
      float height = 3.0;
      Ssbo_inv_view_xform =
          T_translate2(center) *
          T_invView(2.0 * atan(height / 2.0), iResolution.xy);
      Ssbo_c = T_rotate2(M_PI * 7.0 / 12.0) * c_1 * 0.95;
      Ssbo_z0 = vec2(0.0, 0.0);
      Ssbo_use_logistic = 1.0;
    }

    if (0 < iKey) {
      Ssbo_key = iKey;
    }
    if (Ssbo_key == kKeyD) {
      Ssbo_use_logistic = float(!bool(iKeyModifiers & kModifiers[1]));
      Ssbo_key = 0;
    }
    if (mouse_action) {
      if (Ssbo_key == kKeyA) {
        Ssbo_c = vec2(Ssbo_inv_view_xform * vec3(Ssbo_mouse_down_p, 1.0));
      }
      if (Ssbo_key == kKeyS) {
        Ssbo_z0 = vec2(Ssbo_inv_view_xform * vec3(Ssbo_mouse_down_p, 1.0));
      }
    }
  }
#endif

#ifdef COMPILE_mainFragmentDiscard
  layout (location = 0) out vec4 Fragment_color;
  void main() {
    discard;
  }
#endif
