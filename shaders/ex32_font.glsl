//
// "Привет Мир" text rendering with 2d sdf
// cf. https://www.shadertoy.com/view/4s3XDn by Andre
//

#include "common_v0.glsl"
const vec3 OZN = vec3(1.0, 0.0, -1.0);

// window sp size
float AA = 2.0;
float ISOLINE_STEP = 10.0;
float ISOLINE_WIDTH = 1.5;
float ISOLINE_EXTENT = 300.0;

const vec2 BBOX_Y = vec2(-0.75, 1.5);
const vec2 CENTER = vec2(0.5, (BBOX_Y[0] + BBOX_Y[1]) / 2.0);

float Sdf_lineSegment(vec2 p, vec2 v, float t0, float t1) {
  // assert |v| = 1
  return distance(p, clamp(dot(p, v), t0, t1) * v);
}

float Sdf_arc(vec2 p, float r, float t0, float t1) {
  // assert 0 <= t0 < t1 < pi
  float s = mod(atan(p.y, p.x), 2.0 * M_PI);
  float s0 = 2.0 * M_PI * t0;
  float s1 = 2.0 * M_PI * t1;
  if (s0 <= s && s <= s1) {
    return abs(length(p) - r);
  }
  vec2 q1 = r * vec2(cos(s0), sin(s0));
  vec2 q2 = r * vec2(cos(s1), sin(s1));
  return min(distance(p, q1), distance(p, q2));
}

float SdfOp_isoline(float sd, float _step, float width) {
  float t = mod(sd, _step);
  float ud_isoline = min(t, _step - t);
  float sd_isoline = ud_isoline - width / 2.0;
  return sd_isoline;
}

#define SDF_FONT(NAME, RULE) \
  float SdfFont_##NAME(vec2 p) { \
    float ud = 1e30; \
    RULE \
    return ud; \
  }
#define SDF_FONT_LINE(Q1, Q2) \
  ud = min(ud, Sdf_lineSegment(p - (vec2 Q1), normalize(vec2 Q2 - vec2 Q1), 0.0, length(vec2 Q2 - vec2 Q1)));
#define SDF_FONT_ARC(C, R, T1, T2) \
  ud = min(ud, Sdf_arc(p - vec2 C, R, T1, T2));
#define SDF_FONT_POINT(C) \
  ud = min(ud, distance(p, vec2 C));

#define Ym2 -2.0/4.0
#define Ym1 -1.0/4.0
#define Y0  +0.0/4.0
#define Y1  +1.0/4.0
#define Y2  +2.0/4.0
#define Y3  +3.0/4.0
#define Y4  +4.0/4.0

#define dX +1.0/4.0
#define X1 +1.0/4.0
#define X2 +2.0/4.0
#define X3 +3.0/4.0

SDF_FONT(space,)

SDF_FONT(I,
  SDF_FONT_LINE((X1, Y4), (X3, Y4))
  SDF_FONT_LINE((X2, Y4), (X2, Y0))
  SDF_FONT_LINE((X1, Y0), (X3, Y0))
)

SDF_FONT(J,
  SDF_FONT_LINE((X3, Y4), (X3, Y1))
  SDF_FONT_ARC ((X2, Y1), dX, 0.5, 1.0) // rev
)

SDF_FONT(i,
  SDF_FONT_LINE((X1, Y2), (X2, Y2))
  SDF_FONT_LINE((X2, Y2), (X2, Y0))
  SDF_FONT_LINE((X1, Y0), (X3, Y0))
  SDF_FONT_POINT((X2, Y3))
)

SDF_FONT(j,
  SDF_FONT_LINE((X2, Y2), (X3, Y2))
  SDF_FONT_LINE((X3, Y2), (X3, Y0))
  SDF_FONT_ARC((X2, Y0), dX, 0.5, 1.0)
  SDF_FONT_POINT((X3, Y3))
)

SDF_FONT(G,
  SDF_FONT_ARC ((X2, Y3), dX, 0.0, 0.5) // rev
  SDF_FONT_LINE((X1, Y3), (X1, Y1))
  SDF_FONT_ARC ((X2, Y1), dX, 0.5, 1.0)
  SDF_FONT_LINE((X3, Y1), (X3, Y2))
  SDF_FONT_LINE((X2, Y2), (X3, Y2))
)

SDF_FONT(rus_P,
  SDF_FONT_LINE((X1, Y4), (X1, Y0))
  SDF_FONT_LINE((X1, Y4), (X3, Y4))
  SDF_FONT_LINE((X3, Y4), (X3, Y0))
)

SDF_FONT(rus_r,
  SDF_FONT_LINE((X1, Y2), (X1, Ym2))
  SDF_FONT_LINE((X1, Y2), (X2, Y2))
  SDF_FONT_ARC ((X2, Y1), dX, 0.0, 0.25)
  SDF_FONT_ARC ((X2, Y1), dX, 0.75, 1.0)
  SDF_FONT_LINE((X2, Y0), (X1, Y0))
)

SDF_FONT(rus_i,
  SDF_FONT_LINE((X1, Y2), (X1, Y0))
  SDF_FONT_LINE((X1, Y0), (X3, Y2))
  SDF_FONT_LINE((X3, Y2), (X3, Y0))
)

SDF_FONT(rus_b,
  SDF_FONT_LINE((X1, Y2), (X1, Y0))
  SDF_FONT_LINE((X1, Y2), (X2, Y2))
  SDF_FONT_ARC ((X2, Y1 * 1.5), dX * 0.5, 0.0, 0.25)
  SDF_FONT_ARC ((X2, Y1 * 1.5), dX * 0.5, 0.75, 1.0)
  SDF_FONT_LINE((X1, Y1), (X2, Y1))
  SDF_FONT_ARC ((X2, Y1 * 0.5), dX * 0.5, 0.0, 0.25)
  SDF_FONT_ARC ((X2, Y1 * 0.5), dX * 0.5, 0.75, 1.0)
  SDF_FONT_LINE((X1, Y0), (X2, Y0))
)

SDF_FONT(rus_e,
  SDF_FONT_LINE((X1, Y1), (X3, Y1))
  SDF_FONT_ARC ((X2, Y1), dX, 0.0, 7.0/8.0)
)

SDF_FONT(rus_t,
  SDF_FONT_LINE((X1, Y2), (X3, Y2))
  SDF_FONT_LINE((X2, Y2), (X2, Y0))
)

SDF_FONT(rus_M,
  SDF_FONT_LINE((X1, Y4), (X1, Y0))
  SDF_FONT_LINE((X1, Y4), (X2, Y0))
  SDF_FONT_LINE((X2, Y0), (X1, Y4))
  SDF_FONT_LINE((X2, Y0), (X3, Y4))
  SDF_FONT_LINE((X3, Y4), (X3, Y0))
)


#define FOREACH_SYMBOLS(_) \
  _(rus_P) \
  _(rus_r) \
  _(rus_i) \
  _(rus_b) \
  _(rus_e) \
  _(rus_t) \
  _(space) \
  _(rus_M) \
  _(rus_i) \
  _(rus_r) \

#undef SDF_FONT
#undef SDF_FONT_LINE
#undef SDF_FONT_ARC

struct SceneInfo {
  float t;
  float id;
};

SceneInfo mergeSceneInfo(SceneInfo info, float t, float id) {
  info.id = info.t < t ? info.id : id;
  info.t  = info.t < t ? info.t  : t ;
  return info;
}

SceneInfo mainSdf(vec2 p) {
  SceneInfo result;
  result.t = 1e30;

  float index = 0.0;
  #define DRAW(SYMBOL) \
    result = mergeSceneInfo(result, SdfFont_##SYMBOL(p - vec2(index, 0.0)), index++);
  FOREACH_SYMBOLS(DRAW)
  #undef DRAW

  float line_width = 0.1;
  result.t -= line_width / 2.0;
  return result;
}

float smoothCoverage(float signed_distance, float width) {
  return 1.0 - smoothstep(0.0, 1.0, signed_distance / width + 0.5);
}

vec3 easyColor(float t) {
  float s = fract(sin(t * 123456.789) * 123456.789);
  vec3 v = vec3(0.0, 1.0, 2.0) / 3.0;
  vec3 c = 0.5 + 0.5 * cos(2.0 * M_PI * (s - v));
  c = smoothstep(vec3(-0.2), vec3(0.8), c);
  return c;
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // "window -> scene" transform
  float xform_s = (BBOX_Y[1] - BBOX_Y[0]) / iResolution.y;
  vec2 xform_t = vec2(
      CENTER.x - (CENTER.y - BBOX_Y[0]) * iResolution.z,
      BBOX_Y[0]);
  xform_t.x += iTime;

  {
    bool activated, down;
    vec2 last_click_pos, last_down_pos;
    getMouseState(iMouse, activated, down, last_click_pos, last_down_pos);
    if (down) {
      xform_t -= (last_down_pos - last_click_pos) * xform_s;
    }
  }

  vec2 p = frag_coord * xform_s + xform_t;
  bool mouse_down = iMouse.z > 0.5;

  vec3 color = OZN.xxx;
  {
    SceneInfo info = mainSdf(p);
    float fac = smoothCoverage(info.t, AA * xform_s);
    vec3 c = easyColor(info.id);

    if (mouse_down) {
      color = mix(color, c, fac);
    } else {

      //
      // Distance field isolines
      //
      float sd = info.t / xform_s; // to window sp.
      float ud = abs(max(0.0, sd));
      float sd_isoline = SdfOp_isoline(ud, ISOLINE_STEP, ISOLINE_WIDTH);
      float isoline_fac = smoothCoverage(sd_isoline, AA);
      float fade_fac = exp(-7.0 * ud / ISOLINE_EXTENT); // n.b. exp(-7) ~ 0.001
      color = mix(color, c, fade_fac);
      color = mix(color, c * vec3(0.6), isoline_fac * fade_fac);
    }
  }

  {
    //
    // Coordinate system
    //
    {
      // Grid
      float step = 1.0 / 2.0;
      float w = 1.0 * xform_s;
      float sd = 1e30;
      sd = min(sd, SdfOp_isoline(p.x, step, w));
      sd = min(sd, SdfOp_isoline(p.y, step, w));
      float fac = smoothCoverage(sd, AA * xform_s);
      color = mix(color, vec3(0.0), 0.2 * fac);
    }
    {
      // Axis
      float w = 1.0 * xform_s;
      float sd = 1e30;
      sd = min(sd, abs(p.x) - w / 2.0);
      sd = min(sd, abs(p.y) - w / 2.0);
      float fac = smoothCoverage(sd, AA * xform_s);
      color = mix(color, vec3(0.0), fac);
    }
  }

  frag_color = vec4(color, 1.0);
}
