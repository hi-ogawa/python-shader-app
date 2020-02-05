// Clip a line {p0, p1} to a halfspace {u | <u, n> >= 0}
void Overlay_clip4d_Line_HalfSpace(
    vec4 p0, vec4 p1, vec4 n,
    out vec4 q0, out vec4 q1, out bool clipout) {
  // <p + t v, n> = 0  <=> t <v, n> = - <p, n>
  clipout = false;
  vec4 v = p1 - p0;
  float a = dot(v, n);
  float b = dot(p0, n);
  bool p0_in = b > 0;
  float t = - b / a;
  if (p0_in) {
    // [case 1] p0_in && dot(v, n) >= 0
    if (a >= 0) {
      q0 = p0;
      q1 = p1;
      return;
    }
    // [case 2] p0_in && dot(v, n) < 0  (thus t > 0)
    q0 = p0;
    q1 = p0 + min(t, 1.0) * v;
    return;
  }
  // [case 3] !p0_in && dot(v, n) > 0 && t < 1 (thus t > 0)
  if (a > 0 && t < 1) {
    q0 = p0 + t * v;
    q1 = p1;
    return;
  }
  clipout = true;
}

// Clip a line {p0, p1} to "OpenGL's clip volume" (intersection of 7 half spaces)
void Overlay_clip4d_Line_ClipVolume(
    vec4 p0, vec4 p1,
    out vec4 q0, out vec4 q1, out bool clipout) {
  clipout = false;
  q0 = p0;
  q1 = p1;
  vec3 OZN = vec3(1.0, 0.0, -1.0);
  Overlay_clip4d_Line_HalfSpace(q0, q1, OZN.yyyx, q0, q1, clipout); if(clipout) { return; }
  Overlay_clip4d_Line_HalfSpace(q0, q1, OZN.xyyx, q0, q1, clipout); if(clipout) { return; }
  Overlay_clip4d_Line_HalfSpace(q0, q1, OZN.zyyx, q0, q1, clipout); if(clipout) { return; }
  Overlay_clip4d_Line_HalfSpace(q0, q1, OZN.yxyx, q0, q1, clipout); if(clipout) { return; }
  Overlay_clip4d_Line_HalfSpace(q0, q1, OZN.yzyx, q0, q1, clipout); if(clipout) { return; }
  Overlay_clip4d_Line_HalfSpace(q0, q1, OZN.yyxx, q0, q1, clipout); if(clipout) { return; }
  Overlay_clip4d_Line_HalfSpace(q0, q1, OZN.yyzx, q0, q1, clipout);
}

float Overlay_Sdf2_lineSegment(vec2 p, vec2 v, float t0, float t1) {
  // assert |v| = 1
  // assert t0 <= t1
  float t = dot(p, v);
  float s = clamp(t, t0, t1);
  return distance(p, s * v);
}

float Overlay_getLineCoverage(
    vec2 frag_coord, vec2 p0, vec2 p1, float line_width, float aa_px) {
  vec2 p = frag_coord - p0;
  vec2 v = p1 - p0;
  float ud = Overlay_Sdf2_lineSegment(p, normalize(v), 0.0, length(v));
  float sd = ud - line_width / 2.0;
  float fac = 1.0 - smoothstep(0.0, 1.0, sd / aa_px + 0.5);
  return fac;
}

float Overlay_getPointCoverage(
    vec2 frag_coord, vec2 p, float point_radius, float aa_px) {
  float sd = distance(frag_coord, p) - point_radius;
  float fac = 1.0 - smoothstep(0.0, 1.0, sd / aa_px + 0.5);
  return fac;
}

vec4 Overlay_blendInverseAlpha(vec4 p, vec4 q) {
  return vec4(
    mix(p.xyz, q.xyz, q.w),
    p.w * (1 - q.w));
}

void Overlay_clipProjectLine(
    vec3 p0, vec3 p1, mat4 scene_to_clip_xform, mat3 ndc_to_frag_xform,
    bool use_clip, out vec2 v0, out vec2 v1, out bool clipout) {
  clipout = false;
  vec4 q0 = scene_to_clip_xform * vec4(p0, 1.0);
  vec4 q1 = scene_to_clip_xform * vec4(p1, 1.0);
  if (use_clip) {
    Overlay_clip4d_Line_ClipVolume(q0, q1, q0, q1, clipout);
  }
  if (!clipout) {
    v0 = (ndc_to_frag_xform * (q0.xyw / q0.w)).xy;
    v1 = (ndc_to_frag_xform * (q1.xyw / q1.w)).xy;
  }
}

// NOTE:
// we cannot entirely work within normalized coordinate ([-1, 1]^2)
// since that would introduce axis dependent scale, which breaks 2D AA.
vec4 Overlay_coordinateAxisGrid(
    vec2 frag_coord, mat4 scene_to_clip_xform, mat3 ndc_to_frag_xform, float alpha) {
  float BOUND = 8.0; // Axis/grid bound
  float AA_PX = 1.5;
  float LINE_WIDTH = 2.5;
  float POINT_RADIUS = 4.0;

  // inversely multiplied alpha
  vec4 color = vec4(vec3(0.0), 1.0);

  // y = 0 plane grid
  for (int i = 1; i < 2; i++) {
    vec3 grid_color = vec3(1.0);
    int j = (i + 1) % 3;
    int k = (i + 2) % 3;

    for (float s = -BOUND; s < BOUND + 1.0; s++) {
      vec3 p1_a; p1_a[i] = 0, p1_a[j] = s, p1_a[k] =  BOUND;
      vec3 p2_a; p2_a[i] = 0, p2_a[j] = s, p2_a[k] = -BOUND;
      vec3 p1_b; p1_b[i] = 0, p1_b[k] = s, p1_b[j] =  BOUND;
      vec3 p2_b; p2_b[i] = 0, p2_b[k] = s, p2_b[j] = -BOUND;
      {
        vec2 v0, v1;
        bool clipout;
        Overlay_clipProjectLine(
            p1_a, p2_a, scene_to_clip_xform, ndc_to_frag_xform, false,
            v0, v1, clipout);
        if (!clipout) {
          float fac = Overlay_getLineCoverage(
              frag_coord, v0, v1, LINE_WIDTH * 0.5, AA_PX);
          color = Overlay_blendInverseAlpha(color, vec4(grid_color, alpha * fac));
        }
      }
      {
        vec2 v0, v1;
        bool clipout;
        Overlay_clipProjectLine(
            p1_b, p2_b, scene_to_clip_xform, ndc_to_frag_xform, false,
            v0, v1, clipout);
        if (!clipout) {
          float fac = Overlay_getLineCoverage(
              frag_coord, v0, v1, LINE_WIDTH * 0.5, AA_PX);
          color = Overlay_blendInverseAlpha(color, vec4(grid_color, alpha * fac));
        }
      }
    }
  }

  // XYZ axes
  for (int i = 0; i < 3; i++) {
    vec3 p = vec3(0.0); p[i] = 1.0;
    vec3 p0 = +BOUND * p;
    vec3 p1 = -BOUND * p;
    vec2 v0, v1;
    bool clipout;
    Overlay_clipProjectLine(
        p0, p1, scene_to_clip_xform, ndc_to_frag_xform, true,
        v0, v1, clipout);
    if (!clipout) {
      {
        float fac = Overlay_getLineCoverage(
            frag_coord, v0, v1, LINE_WIDTH, AA_PX);
        vec3 axis_color = mix(vec3(0.3), vec3(1.0), p);
        color = Overlay_blendInverseAlpha(color, vec4(axis_color, alpha * fac));
      }
      {
        float fac = Overlay_getPointCoverage(
            frag_coord, v0, POINT_RADIUS, AA_PX);
        vec3 tip_color = p;
        color = Overlay_blendInverseAlpha(color, vec4(tip_color, alpha * fac));
      }
      {
        float fac = Overlay_getPointCoverage(
            frag_coord, v1, POINT_RADIUS * 0.8, AA_PX);
        vec3 tip_color = mix(vec3(0.8), vec3(1.0), p);
        color = Overlay_blendInverseAlpha(color, vec4(tip_color, alpha * fac));
      }
    }
  }
  return color;
}
