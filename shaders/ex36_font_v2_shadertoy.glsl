//
// SDF font from font.svg (for shadertoy)
//

//
// Define font geometry via macro
//

#define M_PI 3.14159

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

#define SDF_FONT(NAME, RULE)     \
  float NAME(vec2 p, float state, out float stroke) { \
    float ud = 1e30;                                     \
    stroke = 0.0;                                        \
    RULE                                                 \
    return ud;                                           \
  }

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

SDF_FONT(en_A,
  SDF_FONT_LINE(0, 4, -1, 0)
  SDF_FONT_LINE(0, 4, 1, 0)
  SDF_FONT_LINE(-0.75, 1, 0.75, 1))

SDF_FONT(en_B,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(-1, 4, 0, 4)
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.25, -0.25)
  SDF_FONT_LINE(0, 2, -1, 2)
  SDF_FONT_ARC (0.0, 1.0, 1.0, 0.25, -0.25)
  SDF_FONT_LINE(0, 0, -1, 0))

SDF_FONT(en_C,
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.0, 0.5)
  SDF_FONT_LINE(-1, 3, -1, 1)
  SDF_FONT_ARC (0.0, 1.0, 1.0, 0.5, 1.0))

SDF_FONT(en_D,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_ARC (-1.0, 2.0, 2.0, 0.25, -0.25))

SDF_FONT(en_E,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(-1, 4, 1, 4)
  SDF_FONT_LINE(-1, 2, 1, 2)
  SDF_FONT_LINE(-1, 0, 1, 0))

SDF_FONT(en_F,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(-1, 4, 1, 4)
  SDF_FONT_LINE(-1, 2, 1, 2))

SDF_FONT(en_G,
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.0, 0.5)
  SDF_FONT_LINE(-1, 3, -1, 1)
  SDF_FONT_ARC (0.0, 1.0, 1.0, 0.5, 1.0)
  SDF_FONT_LINE(1, 1, 1, 2)
  SDF_FONT_LINE(0, 2, 1, 2))

SDF_FONT(en_H,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(-1, 2, 1, 2)
  SDF_FONT_LINE(1, 4, 1, 0))

SDF_FONT(en_I,
  SDF_FONT_LINE(-0.5, 4, 0.5, 4)
  SDF_FONT_LINE(0, 4, 0, 0)
  SDF_FONT_LINE(-0.5, 0, 0.5, 0))

SDF_FONT(en_J,
  SDF_FONT_LINE(0.5, 4, 1.5, 4)
  SDF_FONT_LINE(1, 4, 1, 1)
  SDF_FONT_ARC (0.0, 1.0, 1.0, 0.0, -0.5))

SDF_FONT(en_K,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(1, 4, -1, 2)
  SDF_FONT_LINE(-1, 2, 1, 0))

SDF_FONT(en_L,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(-1, 0, 1, 0))

SDF_FONT(en_M,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(-1, 4, 0, 0)
  SDF_FONT_LINE(0, 0, 1, 4)
  SDF_FONT_LINE(1, 4, 1, 0))

SDF_FONT(en_N,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(-1, 4, 1, 0)
  SDF_FONT_LINE(1, 0, 1, 4))

SDF_FONT(en_O,
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.25, 0.5)
  SDF_FONT_LINE(-1, 3, -1, 1)
  SDF_FONT_ARC (0.0, 1.0, 1.0, 0.5, 1.0)
  SDF_FONT_LINE(1, 1, 1, 3)
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.0, 0.25))

SDF_FONT(en_P,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(-1, 4, 0, 4)
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.25, -0.25)
  SDF_FONT_LINE(0, 2, -1, 2))

SDF_FONT(en_Q,
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.25, 0.5)
  SDF_FONT_LINE(-1, 3, -1, 1)
  SDF_FONT_ARC (0.0, 1.0, 1.0, 0.5, 1.0)
  SDF_FONT_LINE(1, 1, 1, 3)
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.0, 0.25)
  SDF_FONT_LINE(0, 1, 1, 0))

SDF_FONT(en_R,
  SDF_FONT_LINE(-1, 4, -1, 0)
  SDF_FONT_LINE(-1, 4, 0, 4)
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.25, -0.25)
  SDF_FONT_LINE(0, 2, -1, 2)
  SDF_FONT_LINE(0, 2, 1, 0))

SDF_FONT(en_S,
  SDF_FONT_ARC (0.0, 3.0, 1.0, 0.0, 0.75)
  SDF_FONT_ARC (0.0, 1.0, 1.0, 0.25, -0.5))

SDF_FONT(en_T,
  SDF_FONT_LINE(-1, 4, 1, 4)
  SDF_FONT_LINE(0, 4, 0, 0))

SDF_FONT(en_U,
  SDF_FONT_LINE(-1, 4, -1, 1)
  SDF_FONT_ARC (0.0, 1.0, 1.0, 0.5, 1.0)
  SDF_FONT_LINE(1, 1, 1, 4))

SDF_FONT(en_V,
  SDF_FONT_LINE(-1, 4, 0, 0)
  SDF_FONT_LINE(0, 0, 1, 4))

SDF_FONT(en_W,
  SDF_FONT_LINE(-1, 4, -0.5, 0)
  SDF_FONT_LINE(-0.5, 0, 0, 4)
  SDF_FONT_LINE(0, 4, 0.5, 0)
  SDF_FONT_LINE(0.5, 0, 1, 4))

SDF_FONT(en_X,
  SDF_FONT_LINE(-1, 4, 1, 0)
  SDF_FONT_LINE(1, 4, -1, 0))

SDF_FONT(en_Y,
  SDF_FONT_LINE(-1, 4, 0, 2)
  SDF_FONT_LINE(1, 4, 0, 2)
  SDF_FONT_LINE(0, 2, 0, 0))

SDF_FONT(en_Z,
  SDF_FONT_LINE(-1, 4, 1, 4)
  SDF_FONT_LINE(1, 4, -1, 0)
  SDF_FONT_LINE(-1, 0, 1, 0))

#define FONT_LIST_NAMES(_) \
  _(en_A) \
  _(en_B) \
  _(en_C) \
  _(en_D) \
  _(en_E) \
  _(en_F) \
  _(en_G) \
  _(en_H) \
  _(en_I) \
  _(en_J) \
  _(en_K) \
  _(en_L) \
  _(en_M) \
  _(en_N) \
  _(en_O) \
  _(en_P) \
  _(en_Q) \
  _(en_R) \
  _(en_S) \
  _(en_T) \
  _(en_U) \
  _(en_V) \
  _(en_W) \
  _(en_X) \
  _(en_Y) \
  _(en_Z) \

//
// Parameters
//

float SCALE_TIME = 8.0;
float LOOP_TIME = 32.0;
bool  STROKE_MODE = true;

// AA in pixel width
float AA = 2.0;

// isoline effect
float ISOLINE_STEP = 10.0;
float ISOLINE_WIDTH = 1.0;
float ISOLINE_EXTENT = 200.0;

// scene coordinate frame
const vec2 FONT_SIZE = vec2(4.0, 7.0);
const float NUM_COLUMNS = 10.0;
const vec2 BBOX_X = vec2(0.0, FONT_SIZE.x * NUM_COLUMNS) + vec2(-2.0, 2.0);
const float BBOX_Y1 = FONT_SIZE.y;

// font width in scene size
float FONT_WIDTH = 0.4;


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
  float state = STROKE_MODE ? SCALE_TIME * mod(time, LOOP_TIME) : 1e30;
  float len = 0.0;
  float ud;
  vec2 q;
  #define DRAW(NAME)                                                         \
      q = vec2(0.5 + mod(index, NUM_COLUMNS), - floor(index / NUM_COLUMNS)); \
      ud = NAME(p - FONT_SIZE * q, state -= len, len),       \
      result = mergeSceneInfo(result, ud, index++);
    FONT_LIST_NAMES(DRAW)
  #undef DRAW

  result.t -= FONT_WIDTH / 2.0;
  return result;
}

//
// Misc
//

float SdfOp_isoline(float sd, float _step, float width) {
  float t = mod(sd, _step);
  float ud_isoline = min(t, _step - t);
  float sd_isoline = ud_isoline - width / 2.0;
  return sd_isoline;
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

//
// Main
//

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // "window -> scene" transform
  float xform_s = (BBOX_X[1] - BBOX_X[0]) / iResolution.x;
  vec2 xform_t = vec2(
      BBOX_X[0],
      BBOX_Y1 - (BBOX_X[1] - BBOX_X[0]) * (iResolution.y / iResolution.x));

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
