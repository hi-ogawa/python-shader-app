//
// Fatou/Julia set for newton method iteration
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
  vec2 Ssbo_z0;
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
      XXX(min(fract(p.x), 1.0 - fract(p.x)), OZN.xy, 1.0, OZN.xxx * 0.2)
      XXX(min(fract(p.y), 1.0 - fract(p.y)), OZN.yx, 1.0, OZN.xxx * 0.2)
      XXX(abs(p.x),                          OZN.xy, 2.0, OZN.xyy * 0.2)
      XXX(abs(p.y),                          OZN.xy, 2.0, OZN.yxy * 0.2)

    #undef XXX
    #undef MERGE_SD
  }

  vec4 renderPixel(vec2 frag_coord) {
    mat3 inv_view_xform = Ssbo_inv_view_xform;
    mat3 view_xform = inverse(inv_view_xform);

    float AA = 1.5;
    vec3 color = OZN.yyy;
    vec2 p = vec2(inv_view_xform * vec3(frag_coord, 1.0));
    int n = 3;
    mat2 dpdw = mat2(inv_view_xform);

    // Draw coordinate grid
    {
      float sd_tmp; vec3 color_tmp;
      coordinate2d(p, mat2(inv_view_xform), sd_tmp, color_tmp);
      color = mixColor(color, color_tmp, sdToFactor(sd_tmp, AA));
    }

    // Draw Fatou/Julia set
    {
      // p(z) = z^n - 1
      // p'(z) = n z^{n-1}
      // f(z) = z - p(z) / p'(z) = ((n - 1) z^n + 1) / n z^{n - 1}
      vec2 z = p;
      int kIterMax = 1024;
      int iter = 0;
      for (; iter < kIterMax; iter++) {
        vec2 zz = c_pow(z, n - 1);
        vec2 zzz = c_mul(z) * zz;
        if (dot2(zzz - c_1) < 1e-3) { break; }
        z = c_mul(c_inv(float(n) * zz)) * (float(n - 1) * zzz + c_1);
      }
      vec3 iter_color = OZN.yyy;
      iter_color += Misc_hue(atan(z.y, z.x) / (2.0 * M_PI) - M_PI / 6.0);
      iter_color *= 0.5 + 0.5 * cos(0.2 * float(iter));
      color += iter_color;
      // [ Bottcher coord ] actually not well-defined for entire basin so not useful
      if (dot2(z - c_1) < 1e-3) {
        vec2 w = z - c_1;
        float t_w = atan(w.y, w.x);

        // Iterating back (for Bottcher coord, this corresponds to taking square root)
        float t = t_w / pow(2.0, iter);

        // Gave up using this
        // color += Misc_hue(t / (2.0 * M_PI));
      }
    }

    // Draw iteration from z0
    {
      const int kNumIter = 16;
      vec2 zs[kNumIter];
      zs[0] = Ssbo_z0;
      for (int i = 1; i < kNumIter; i++) {
        vec2 z = zs[i - 1];
        vec2 zz = c_pow(z, n - 1);
        vec2 zzz = c_mul(z) * zz;
        zs[i] = c_mul(c_inv(float(n) * zz)) * (float(n - 1) * zzz + c_1);
      }

      for (int i = 0; i < kNumIter; i++) {
        vec2 z = zs[i];
        if (1e3 < length(z)) { break; }

        float ud = length(p - z) / length(normalize(p - z) * dpdw);
        float fac = udToFactor(ud, 6.0, AA);
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
      float height = 6.0;
      Ssbo_inv_view_xform =
          T_translate2(center) *
          T_invView(2.0 * atan(height / 2.0), iResolution.xy);
      Ssbo_z0 = vec2(1.0, 1.0);
    }

    if (0 < iKey) {
      Ssbo_key = iKey;
    }
    if (mouse_action) {
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
