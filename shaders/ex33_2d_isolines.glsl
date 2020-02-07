//
// 2d isolines
//

#define M_PI 3.14159
const vec3 OZN = vec3(1.0, 0.0, -1.0);

// window sp size
float AA = 2.0;
float ISOLINE_STEP = 10.0;
float ISOLINE_WIDTH = 2.0;
float ISOLINE_EXTENT = 300.0;

float Sdf_lineSegment2d(vec2 p, vec2 v, float t0, float t1) {
  // assert |v| = 1
  return distance(p, clamp(dot(p, v), t0, t1) * v);
}

float Sdf_box2d(vec2 p, vec2 b) {
  vec2 d2 = abs(p) - b;
  float m = max(d2.x, d2.y);
  return m < 0.0 ? m : length(max(d2, vec2(0.0)));
}

float Sdf_disk(vec2 p, float r) {
  return length(p) - r;
}

float SdfOp_isoline(float sd, float _step, float width) {
  float t = mod(sd, _step);
  float ud_isoline = min(t, _step - t);
  float sd_isoline = ud_isoline - width / 2.0;
  return sd_isoline;
}

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
  {
    vec2 loc = vec2(0.6, 0.5);
    vec2 v = normalize(vec2(1.0, -1.0));
    float l = 0.3;
    float line_width = 0.1;
    float sd = Sdf_lineSegment2d(p - loc, v, 0.0, l) - line_width / 2.0;
    result = mergeSceneInfo(result, sd, float(__LINE__));
  }
  {
    vec2 loc = vec2(0.25, 0.35);
    vec2 b = vec2(0.2, 0.25);
    float sd = Sdf_box2d(p - loc, b);
    result = mergeSceneInfo(result, sd, float(__LINE__));
  }
  {
    vec2 loc = vec2(0.8, 0.65);
    float r = 0.15;
    float sd = Sdf_disk(p - loc, r);
    result = mergeSceneInfo(result, sd, float(__LINE__));
  }
  return result;
}

float smoothCoverage(float signed_distance, float width) {
  return 1.0 - smoothstep(0.0, 1.0, signed_distance / width + 0.5);
}

vec3 easyColor(float t) {
  float s = fract(sin(t * 123456.789) * 123456.789);
  vec3 v = vec3(0.0, 1.0, 2.0) / 3.0;
  vec3 c = 0.5 + 0.5 * cos(2.0 * M_PI * (s - v));
  c = smoothstep(vec3(-0.1), vec3(0.9), c);
  return c;
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // "window -> scene" transform
  // [0, W] x [0, H]  ->  [-AR/2, 1 + AR/2] x [0, 1]
  float xform_s = 1.0 / iResolution.y;
  vec2 xform_t = vec2((iResolution.z - 1.0) / 2.0, 0.0);
  vec2 p = frag_coord * xform_s - xform_t;
  bool mouse_down = iMouse.z > 0.5;

  vec3 color = OZN.xxx;
  {
    SceneInfo info = mainSdf(p);
    float fac = smoothCoverage(info.t, AA * xform_s);
    vec3 c = easyColor(info.id);

    if (mouse_down) {
      color = mix(color, c, fac);
    } else {
      float sd = info.t / xform_s; // to window sp.
      float ud = abs(max(0.0, sd));
      float sd_isoline = SdfOp_isoline(ud, ISOLINE_STEP, ISOLINE_WIDTH);
      float isoline_fac = smoothCoverage(sd_isoline, AA);
      float fade_fac = exp(-7.0 * ud / ISOLINE_EXTENT); // n.b. exp(-7) ~ 0.001
      color = mix(color, c, fade_fac);
      color = mix(color, c * vec3(0.6), isoline_fac * fade_fac);
    }
  }
  frag_color = vec4(color, 1.0);
}
