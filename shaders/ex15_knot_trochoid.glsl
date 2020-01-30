//
// Knotted Hyper/Epi-Trochoid
//

#define M_PI 3.14159

float AA = 2.0;
float SCALE_TIME = 1.5;
vec2  UV_CENTER = vec2(0.0, 0.0);
float UV_HEIGHT = 2.2;

float CHECKER_SCALE = 1.0;
vec3  CHECKER_COLOR0 = vec3(0.1);
vec3  CHECKER_COLOR1 = vec3(0.2);

const float kEpi = 0.0;
const float kHyper = 1.0;

const float EPI_OR_HYPER = kEpi;
float NUM_SYMMETRY = 3.0;
const float NUM_POINTS = 128.0 * (EPI_OR_HYPER == kEpi ? 2.0 : 1.0);
float POINT_RADIUS = M_PI / NUM_POINTS * (EPI_OR_HYPER == kEpi ? 2.0 : 0.9);
vec4  TROCHOID_COLOR = vec4(0.8, 1.0, 1.0, 0.9);

//
// Re-parameterize hyper/epi-trochoid for easier visual control
//
//   "num_symmetry"
//     n = r1 / r2 = 1 / r2 \in N
//
//   "knotness" (knot (a > 1), intersecton (1 > a > 0), no-intersection (0 > a))
//     r3 = (1 - a) r2 + a * (r1 - r2)  (for hyper-trochoid)
//     r3 = (1 - a) r2 + a * (r1 + r2)  (for epi-trochoid)
//
// TODO:
// - reduce loop by taking symmetry into account
// - for higher n, there is different kind of qualitative change (e.g. intersection with neighbor).
//
float signedDistanceToKnottedTrochoidPoints(
    vec2 p, float trochoid_type, float knotness, float num_symmetry,
    float num_points, float point_radius, float knot_offset) {

  float r1 = 1.0;
  float r2 = 1.0 / num_symmetry;
  float r3, size; {
    if (trochoid_type == kHyper) {
      r3 = (1.0 - knotness) * r2 + knotness * (r1 - r2);
      size = r1 - r2 + r3;
    }
    if (trochoid_type == kEpi) {
      r3 = (1.0 - knotness) * r2 + knotness * (r1 + r2);
      size = r1 + r2 + r3;
    }
  }
  r1 /= size; r2 /= size; r3 /= size;

  float min_distance = 1000.0;
  for (float i = 0.0; i < num_points; i++) {
    float t = 2.0 * M_PI * i / num_points;
    vec3 q; {
      if (trochoid_type == kHyper) {
        q = vec3(
          // usual hyper-trochoid formula
          (r1 - r2) * cos(t) + r3 * cos((1.0 - num_symmetry) * t),
          (r1 - r2) * sin(t) + r3 * sin((1.0 - num_symmetry) * t),
          // knot by waving z coord along symmetry
          sin(num_symmetry * (t + knot_offset)));
      }
      if (trochoid_type == kEpi) {
        q = vec3(
          // usual epi-trochoid formula
          (r1 + r2) * cos(t) + r3 * cos((1.0 + num_symmetry) * t - M_PI),
          (r1 + r2) * sin(t) + r3 * sin((1.0 + num_symmetry) * t - M_PI),
          // knot by waving z coord along symmetry
          sin(num_symmetry * (t + knot_offset)));
      }
    }
    float radius = point_radius * mix(0.6, 1.0, q.z);
    float sd = distance(p, q.xy) - radius;
    if (sd < min_distance) {
      min_distance = sd;
    }
  }
  return min_distance;
}


//
// Misc
//

float signedDistanceToChecker(vec2 uv, float scale) {
  uv *= scale;
  vec2 uvi = floor(uv);
  vec2 uvf = uv - uvi;
  float dist = min(min(min(uvf.x, uvf.y), 1.0 - uvf.x), 1.0 - uvf.y);
  dist /= scale;
  bool is_even_spot = mod(uvi.x + uvi.y, 2.0) == 0.0;
  return is_even_spot ? -dist : dist;
}

mat3 invViewTransform(vec2 center, float height) {
  vec2 Res = iResolution.xy;
  vec2 size = vec2(height * Res.x / Res.y, height);
  vec2 a = center - size / 2.0;
  float Sy = height / Res.y;
  mat3 xform = mat3(
       Sy,   0,   0,
        0,  Sy,   0,
      a.x, a.y, 1.0);
  return xform;
}

float smoothBoundaryCoverage(float signed_distance, float boundary_width) {
  return 1.0 - smoothstep(0.0, 1.0, signed_distance / boundary_width + 0.5);
}


//
// Main
//

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  mat3 inv_view_xform = invViewTransform(UV_CENTER, UV_HEIGHT);
  float inv_view_scale = inv_view_xform[0][0];
  vec2 uv =  vec2(inv_view_xform * vec3(frag_coord, 1.0));
  float t = SCALE_TIME * iTime;

  vec3 color;
  {
    // Checker
    float sd = signedDistanceToChecker(uv, CHECKER_SCALE);
    float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
    color = mix(CHECKER_COLOR0, CHECKER_COLOR1, coverage);
  }
  {
    // Hyper/Epi-Trochoid
    float knotness = 3.0 * (0.5 + 0.5 * sin(t));
    float knot_offset = 0.0; // not used now
    float sd = signedDistanceToKnottedTrochoidPoints(
        uv, EPI_OR_HYPER, knotness, NUM_SYMMETRY, NUM_POINTS, POINT_RADIUS, knot_offset);
    float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
    color = mix(color, TROCHOID_COLOR.xyz, TROCHOID_COLOR.w * coverage);
  }
  frag_color = vec4(color, 1.0);
}
