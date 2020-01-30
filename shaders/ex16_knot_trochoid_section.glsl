//
// 2D Section of Rotating Knotted Hyper/Epi-Trochoid
//
// NOTE:
// - "ROT_VELOCITY" here doesn't necessarily give angular velocity around any axis
//   since this is a derivative of extrinsic rotation angles xyz in this order.
//   This might be the reason why "vec3(M_PI, M_PI, M_PI)" already does crazy stuff.
// - Surprisingly "Hyper" and "Epi" give visually similar results.
//   But, "Epi" requires more points to approximate curve since "Epi" curve is longer thant "Hyper".
//   So "Hyper" might be the ones should be used.
// - "KNOTNESS > 1.0" and "KNOTNESS < 1.0" give quite different results as expected.
//

#define M_PI 3.14159

float AA = 2.0;
float SCALE_TIME = 0.5;
vec2  UV_CENTER = vec2(0.0, 0.0);
float UV_HEIGHT = 3.0;

float CHECKER_SCALE = 1.0;
vec3  CHECKER_COLOR0 = vec3(0.1);
vec3  CHECKER_COLOR1 = vec3(0.2);
vec4  SECTION_COLOR = vec4(0.8, 1.0, 1.0, 0.9);

const float kEpi = 0.0;
const float kHyper = 1.0;

// == Curve parameter ==
// [ KNOTNESS > 1.0 ]
const float EPI_OR_HYPER = kHyper;
float NUM_SYMMETRY = 4.0;
float KNOTNESS = 2.5;
float NUM_SEGMENTS = 128.0 * (EPI_OR_HYPER == kEpi ? 2.0 : 1.0);
float BEBEL_WIDTH = 0.15;

// [ KNOTNESS < 1.0 ]
// const float EPI_OR_HYPER = kHyper;
// float NUM_SYMMETRY = 3.0;
// float KNOTNESS = 0.2;
// float NUM_SEGMENTS = 128.0 * (EPI_OR_HYPER == kEpi ? 2.0 : 1.0);
// float BEBEL_WIDTH = 0.15;

// == Rotation ==
// vec3  ROT_VELOCITY = vec3(M_PI, 0.0,  0.0);
// vec3  ROT_VELOCITY = vec3(M_PI, 0.0,  M_PI);
// vec3  ROT_VELOCITY = vec3(M_PI, M_PI, 0.0);
vec3  ROT_VELOCITY = vec3(M_PI, M_PI, M_PI);
// vec3  ROT_VELOCITY = vec3(M_PI, M_PI, 0.5 * M_PI);
// vec3  ROT_VELOCITY = vec3(M_PI, M_PI * 4.0 / 3.0, M_PI * 5.0/ 4.0);


float distance_Point_LineSegment(vec3 p, vec3 q1, vec3 q2) {
  // < p - (q + t v), v> = 0  <=>  t = < p - q, v > / < v, v >
  vec3 v = q2 - q1;
  float dot_vv = dot(v, v);
  if (dot(v, v) < 0.0000001) {
    return distance(p, q1);
  }
  float t = dot(p - q1, v) / dot_vv;
  float s = clamp(t, 0.0, 1.0);
  return distance(p, q1 + s * v);
}

vec3 knottedTrochoidPoint(float t, float r1, float r2, float r3, float type) {
  float n = r1 / r2;
  vec3 q;
  if (type == kHyper) {
    q = vec3(
      // usual hyper-trochoid formula
      (r1 - r2) * cos(t) + r3 * cos((1 - n) * t),
      (r1 - r2) * sin(t) + r3 * sin((1 - n) * t),
      // knot by waving z coord along symmetry
      sin(n * t));
  }
  if (type == kEpi) {
    q = vec3(
      // usual epi-trochoid formula
      (r1 + r2) * cos(t) + r3 * cos((1.0 + n) * t - M_PI),
      (r1 + r2) * sin(t) + r3 * sin((1.0 + n) * t - M_PI),
      // knot by waving z coord along symmetry
      sin(n * t));
  }
  return q;
}

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
float signedDistanceToKnottedTrochoid(
    vec3 p, float type, float knotness, float num_symmetry,
    float num_segments, float bebel_width) {

  // Take care reparameterization and normalize overall size to about [-1, 1]^2
  float r1 = 1.0;
  float r2 = 1.0 / num_symmetry;
  float r3, size; {
    if (type == kHyper) {
      r3 = (1.0 - knotness) * r2 + knotness * (r1 - r2);
      size = r1 - r2 + r3;
    }
    if (type == kEpi) {
      r3 = (1.0 - knotness) * r2 + knotness * (r1 + r2);
      size = r1 + r2 + r3;
    }
  }
  r1 /= size; r2 /= size; r3 /= size;

  // Approximate distance by straight lines
  float min_distance = 1000.0;

  vec3 q1, q2;
  q1 = knottedTrochoidPoint(0.0, r1, r2, r3, type);

  bool OPTIM_LOOP_WITH_SYMMETRY = true;
  if (OPTIM_LOOP_WITH_SYMMETRY) {
    // NOTE: It seems this approach is a bit faster.
    for (float i = 1.0; i < num_segments / num_symmetry + 1.0; i++) {
      float t = 2.0 * M_PI * i / num_segments;
      q2 = knottedTrochoidPoint(t, r1, r2, r3, type);
      for (float j = 0.0; j < num_symmetry; j++) {
        float s = 2.0 * M_PI * j / num_symmetry;
        mat2 rot = mat2(cos(s), sin(s), -sin(s), cos(s));
        vec3 v1 = vec3(rot * q1.xy, q1.z);
        vec3 v2 = vec3(rot * q2.xy, q2.z);
        float sd = distance_Point_LineSegment(p, v1, v2) - bebel_width;
        min_distance = min(min_distance, sd);
      }
      q1 = q2;
    }

  } else {
    vec3 q1, q2;
    q1 = knottedTrochoidPoint(0.0, r1, r2, r3, type);
    for (float i = 1.0; i < num_segments + 1.0; i++) {
      float t = 2.0 * M_PI * i / num_segments;
      q2 = knottedTrochoidPoint(t, r1, r2, r3, type);
      float sd = distance_Point_LineSegment(p, q1, q2) - bebel_width;
      min_distance = min(min_distance, sd);
      q1 = q2;
    }
  }
  return min_distance;
}


//
// Misc
//

mat2 rot2(float t) {
  return mat2(cos(t), sin(t), -sin(t), cos(t));
}

mat3 rot3(vec3 r) {
  mat2 x = rot2(r.x);
  mat2 y = rot2(r.y);
  mat2 z = rot2(r.z);
  mat3 X = mat3(
      1.0,     0.0,     0.0,
      0.0, x[0][0], x[0][1],
      0.0, x[1][0], x[1][1]);
  mat3 Y = mat3(
    y[1][1],   0.0, y[0][1],
        0.0,   1.0,     0.0,
    y[1][0],   0.0, y[0][0]);
  mat3 Z = mat3(
    z[0][0], z[0][1],   0.0,
    z[1][0], z[1][1],   0.0,
        0.0,     0.0,   1.0);
  return Z * Y * X;
}

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
    // Animate transform and coordinate
    mat4 obj_xform = mat4(rot3(ROT_VELOCITY * t));
    vec3 p = vec3(uv, 0.0);
    vec3 p_in_obj = vec3(inverse(obj_xform) * vec4(p, 1.0));

    // Approximate 2d section distance by 3d distance
    float sd = signedDistanceToKnottedTrochoid(
        p_in_obj, EPI_OR_HYPER, KNOTNESS, NUM_SYMMETRY, NUM_SEGMENTS, BEBEL_WIDTH);
    float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
    color = mix(color, SECTION_COLOR.xyz, SECTION_COLOR.w * coverage);
  }

  frag_color = vec4(color, 1.0);
}
