//
// SDF font from font.svg
//

#include "common_v0.glsl"


//
// Parameters
//

float SCALE_TIME = 8.0;
bool  STROKE_MODE = true;

// AA in pixel width
float AA = 2.0;

// isoline effect
float ISOLINE_STEP = 10.0;
float ISOLINE_WIDTH = 1.0;
float ISOLINE_EXTENT = 200.0;

// scene coordinate frame
const vec2 FONT_SIZE = vec2(4.0, 7.0);
const float NUM_ROWS = 8.0;
const float NUM_COLUMNS = 9.0;
const vec2 BBOX_X = vec2(0.0, FONT_SIZE.x * NUM_COLUMNS) + vec2(-2.0, 2.0);
const float BBOX_Y1 = FONT_SIZE.y;

// font width in scene size
float FONT_WIDTH = 0.4;


//
// Sdf routines
//

float Sdf_lineSegment(vec2 p, vec2 v, float t0, float t1) {
  // assert |v| = 1
  return distance(p, clamp(dot(p, v), t0, t1) * v);
}

float Sdf_arc(vec2 p, float t0, float t1) {
  //
  // "Arc" defined as a path of winding map:
  //   R --> S1
  //   t |-> (cos(2pi t), sin(2pi t))
  //
  // Thus, sign(t1 - t0) gives orientation i.e.
  //   t1 >= t0  (counter clock wise)
  //   t0 >= t1  (clock wise)
  //
  float t  = atan(p.y, p.x) / (2.0 * M_PI); // in [-0.5, 0.5]
  float tt = mod(t - t0, 1.0) + t0;         // in [t0, t0 + 1]

  // Check if "(0, 0) -> p" crosses arc
  if ((t0 <= t1 && tt <= t1) || (t1 <= t0 && t1 <= tt - 1.0)) {
    return abs(length(p) - 1.0);
  }

  // Otherwise return distance to two endpoints
  vec2 q1 = vec2(cos(2.0 * M_PI * t0), sin(2.0 * M_PI * t0));
  vec2 q2 = vec2(cos(2.0 * M_PI * t1), sin(2.0 * M_PI * t1));
  return min(distance(p, q1), distance(p, q2));
}

float SdfOp_isoline(float sd, float _step, float width) {
  float t = mod(sd, _step);
  float ud_isoline = min(t, _step - t);
  float sd_isoline = ud_isoline - width / 2.0;
  return sd_isoline;
}


//
// Define font geometry via macro (define SdfFont_xxx and SdfFontStroke_xxx)
//

#define SDF_FONT(NAME, RULE)     \
  float SdfFont_##NAME(vec2 p) { \
    float ud = 1e30;             \
    RULE                         \
    return ud;                   \
  }

#define SDF_FONT_LINE(x0, y0, x1, y1) \
  ud = min(ud, Sdf_lineSegment(p - (vec2(x0, y0)), normalize(vec2(x1, y1) - vec2(x0, y0)), 0.0, length(vec2(x1, y1) - vec2(x0, y0))));

#define SDF_FONT_ARC(cx, cy, r, t0, t1) \
  ud = min(ud, Sdf_arc((p - vec2(cx, cy)) / r, t0, t1) * r);

// this calls SDF_FONT macro (also defines FONT_LIST_NAMES, FONT_NUM_NAMES, etc...)
#include "utils/font_data_v0.glsl"


#undef SDF_FONT
#define SDF_FONT(NAME, RULE)     \
  float SdfFontStroke_##NAME(vec2 p, float state, out float stroke) { \
    float ud = 1e30;                                     \
    stroke = 0.0;                                        \
    RULE                                                 \
    return ud;                                           \
  }

#undef SDF_FONT_LINE
#define SDF_FONT_LINE(x0, y0, x1, y1) \
  {                                                                    \
    vec2 v = vec2(x1, y1) - vec2(x0, y0);                              \
    float l = length(v);                                               \
    float ll = min(state - stroke, l);                                 \
    if (ll > 0.0) {                                                    \
      ud = min(ud, Sdf_lineSegment(p - vec2(x0, y0), v / l, 0.0, ll)); \
    }                                                                  \
    stroke += l;                                                       \
  }

#undef SDF_FONT_ARC
#define SDF_FONT_ARC(cx, cy, r, t0, t1) \
  {                                                                       \
    float s = sign(t1 - t0);                                              \
    float l = r * 2.0 * M_PI * abs(t1 - t0);                              \
    float ll = min(state - stroke, l);                                    \
    float tt = ll / (r * 2.0 * M_PI);                                     \
    if (tt > 0.0) {                                                       \
      ud = min(ud, Sdf_arc((p - vec2(cx, cy)) / r, t0, t0 + s * tt) * r); \
    }                                                                     \
    stroke += l;                                                          \
  }


// include again to define different variant
#undef FONT_LIST_NAMES
#undef FONT_NUM_NAMES
#include "utils/font_data_v0.glsl"


//
// Implement scene
//

struct SceneInfo {
  float t;
  float id;
};

SceneInfo mergeSceneInfo(SceneInfo info, float t, float id) {
  info.id = info.t < t ? info.id : id;
  info.t  = info.t < t ? info.t  : t ;
  return info;
}

SceneInfo getSceneSdf(vec2 p, float time) {
  SceneInfo result;
  result.t = 1e30;

  float index = 0.0;
  if (STROKE_MODE) {
    float state = SCALE_TIME * time;
    float len = 0.0;
    float ud;
    vec2 q;
    #define DRAW(NAME)                                                         \
        q = vec2(0.5 + mod(index, NUM_COLUMNS), - floor(index / NUM_COLUMNS)); \
        ud = SdfFontStroke_##NAME(p - FONT_SIZE * q, state -= len, len),       \
        result = mergeSceneInfo(result, ud, index++);
      FONT_LIST_NAMES(DRAW)
    #undef DRAW

  } else {
    float ud;
    vec2 q;
    #define DRAW(NAME)                                                         \
        q = vec2(0.5 + mod(index, NUM_COLUMNS), - floor(index / NUM_COLUMNS)); \
        ud = SdfFont_##NAME(p - FONT_SIZE * q);                                \
        result = mergeSceneInfo(result, ud, index++);
      FONT_LIST_NAMES(DRAW)
    #undef DRAW
  }


  result.t -= FONT_WIDTH / 2.0;
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
  float xform_s = (BBOX_X[1] - BBOX_X[0]) / iResolution.x;
  vec2 xform_t = vec2(
      BBOX_X[0],
      BBOX_Y1 - (BBOX_X[1] - BBOX_X[0]) / iResolution.z);

  {
    // Support move by mouse
    bool activated, down;
    vec2 last_click_pos, last_down_pos;
    getMouseState(iMouse, activated, down, last_click_pos, last_down_pos);
    if (down) {
      xform_t -= (last_down_pos - last_click_pos) * xform_s;
    }
  }

  vec2 p = frag_coord * xform_s + xform_t;
  bool mouse_down = iMouse.z > 0.5;

  vec3 color = vec3(1.0);
  {
    //
    // Main rendering
    //
    SceneInfo info = getSceneSdf(p, iTime);
    float fac = smoothCoverage(info.t, AA * xform_s);
    vec3 c = easyColor(info.id);

    if (mouse_down) {
      color = mix(color, c, fac);
    } else {

      //
      // Fancy isolines
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
    // Coordinate grid
    //
    {
      // Grid
      float step = 1.0;
      float w = 1.0 * xform_s;
      float sd = 1e30;
      sd = min(sd, SdfOp_isoline(p.x, step, w));
      sd = min(sd, SdfOp_isoline(p.y, step, w));
      float fac = smoothCoverage(sd, AA * xform_s);
      color = mix(color, vec3(0.0), 0.1 * fac);
    }
    {
      // Axis
      float w = 1.0 * xform_s;
      float sd = 1e30;
      sd = min(sd, SdfOp_isoline(p.x, FONT_SIZE.x, w));
      sd = min(sd, SdfOp_isoline(p.y, FONT_SIZE.y, w));
      float fac = smoothCoverage(sd, AA * xform_s);
      color = mix(color, vec3(0.0), 0.4 * fac);
    }
  }

  frag_color = vec4(color, 1.0);
}
