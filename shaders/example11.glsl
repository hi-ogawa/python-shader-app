//
// Signed circumcircle
//
// NOTE:
//   I can canonically obtain "sign" based on "InCircle test",
//   but it doesn't give canonical AA friendly pixel value
//   since it is the volume of a tetrahedra in a quite unrelated 3d space.
//   So, "USE_IN_CIRCLE_TEST = false" switches to direct computation
//   of circumcircle and signed area of a triangle.
//

#define M_PI 3.14159

bool USE_IN_CIRCLE_TEST = true;
float IN_CIRCLE_TEST_VOLUME_SCALE = 1000.0;

float SCALE = 1.2;
float SCALE_TIME = .5;

float CHECKER_SCALE = 4.0;
vec3  CHECKER_COLOR0 = vec3(0.20);
vec3  CHECKER_COLOR1 = vec3(0.60);

float POINT_RADIUS = 3.0;
vec3  POINT_COLOR = vec3(0.0, 1.0, 1.0);

vec3  TRIANGLE_COLOR = vec3(0.0, 1.0, 1.0);
float TRIANGLE_ALPHA = 0.75;

vec3  DISK_COLOR = vec3(1.0);
float DISK_ALPHA = 0.75;

float AA = 2.0;

//
// Utils
//

vec2 unitVector2(float t) {
  return vec2(cos(2.0 * M_PI * t), sin(2.0 * M_PI * t));
}
float mix2(float f00, float f10, float f01, float f11, vec2 uv) {
  return mix(mix(f00, f10, uv[0]), mix(f01, f11, uv[0]), uv[1]);
}

void intersect_Line_Line(
    vec2 p1, vec2 v1, vec2 p2, vec2 v2,
    out float t1, out float t2) {
  // assume v1, v2: linear indep.
  // p1 + t1 v1 = p2 + t2 v2
  // <=>  (p1 - p2) + [v1, -v2] {t1, t2} = 0
  // <=>  {t1, t2} = inv([v1, -v2]) (-p1 + p2)
  vec2 t1t2 = inverse(mat2(v1, -v2)) * (-p1 + p2);
  t1 = t1t2[0];
  t2 = t1t2[1];
}

float distance_Point_LineSegment(vec2 p, vec2 q1, vec2 q2) {
  // < p - (q + t v), v> = 0  <=>  t = < p - q, v > / < v, v >

  vec2 v = q2 - q1;
  float dot_vv = dot(v, v);
  if (dot(v, v) < 0.0001) {
    return distance(p, q1);
  }
  float t = dot(p - q1, v) / dot_vv;
  float s = clamp(t, 0.0, 1.0);
  return distance(p, q1 + s * v);
}


//
// Noise
//

float hash11(float t) {
  return fract(sin(1.0 + t * 123456.789) * 123456.789);
}

float hash21(vec2 v) {
  return hash11(hash11(v[0]) + 2.0 * hash11(v[1]));
}

vec2 hash12(float v) {
  return vec2(hash11(v), hash21(vec2(v, 1.0)));
}

vec2 hashGradient2(vec2 uv) {
  return unitVector2(hash21(uv));
}

float gradientNoise2(vec2 uv) {
  vec2 uvi = floor(uv);
  vec2 uvf = uv - uvi;
  float f00 = dot(hashGradient2(uvi + vec2(0.0, 0.0)), uvf - vec2(0.0, 0.0));
  float f10 = dot(hashGradient2(uvi + vec2(1.0, 0.0)), uvf - vec2(1.0, 0.0));
  float f01 = dot(hashGradient2(uvi + vec2(0.0, 1.0)), uvf - vec2(0.0, 1.0));
  float f11 = dot(hashGradient2(uvi + vec2(1.0, 1.0)), uvf - vec2(1.0, 1.0));
  float t = mix2(f00, f10, f01, f11, smoothstep(vec2(0.0), vec2(1.0), uvf));
  return (t / 0.7 + 1.0) * 0.5;
}

vec2 someNoise(float hash_seed, float conti_seed) {
  // Taking hashed direction to break inherent velocity pattern of gradientNoise2
  vec2 p = hash12(hash_seed);
  vec2 dir1 = unitVector2(p[0]);
  vec2 dir2 = unitVector2(p[1]);
  vec2 v = vec2(
      gradientNoise2(123.456 * vec2(hash_seed) + 456.789 + conti_seed * dir1),
      gradientNoise2(456.123 * vec2(hash_seed) + 789.456 + conti_seed * dir2));

  // Tonemap [0, 1] to make movement more "dynamical"
  return smoothstep(0.0, 1.0, v);
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

float signedDistanceToTriangle(vec2 uv, vec2 p0, vec2 p1, vec2 p2) {
  vec2 v1 = p1 - p0;
  vec2 v2 = p2 - p0;
  float signed_area = cross(vec3(v1, 0.0), vec3(v2, 0.0)).z;
  if (abs(signed_area) <= 0.0000001) {
    return 1000.0;
  }

  // Barycentric coord (uv = p0 + s * v1 + t * v2)
  mat2 v1v2 = mat2(v1, v2);
  vec2 st = inverse(transpose(v1v2) * v1v2) * transpose(v1v2) * (uv - p0);
  bool is_inside = st.x >= 0.0 && st.y >= 0.0 && (st.x + st.y) <= 1.0;

  float dist = 1000.0;
  dist = min(dist, distance_Point_LineSegment(uv, p0, p1));
  dist = min(dist, distance_Point_LineSegment(uv, p1, p2));
  dist = min(dist, distance_Point_LineSegment(uv, p2, p0));

  return is_inside ? -dist : dist;
}

float signedDistanceToCircle(vec2 uv, vec2 center, float radius) {
  return distance(uv, center) - radius;
}

float inCircleTestVolume(vec2 q, vec2 p0, vec2 p1, vec2 p2) {
  mat3 circle_test_mat = mat3(
    (p0 - q).x, (p0 - q).y, dot(p0, p0) - dot(q, q),
    (p1 - q).x, (p1 - q).y, dot(p1, p1) - dot(q, q),
    (p2 - q).x, (p2 - q).y, dot(p2, p2) - dot(q, q));
  float circle_test_det = determinant(circle_test_mat);
  return circle_test_det;
}

vec2 circumcircleCenter(vec2 p0, vec2 p1, vec2 p2) {
  // assume non degenerate triangle
  vec2 q1 = (p0 + p1) / 2.0;
  vec2 q2 = (p0 + p2) / 2.0;
  vec2 u1 = p1 - p0;
  vec2 u2 = p2 - p0;
  vec2 v1 = vec2(cross(vec3(0.0, 0.0, 1.0), vec3(u1, 0.0)));
  vec2 v2 = vec2(cross(vec3(0.0, 0.0, 1.0), vec3(u2, 0.0)));
  float t1, t2;
  intersect_Line_Line(q1, v1, q2, v2, t1, t2);
  return q1 + t1 * v1;
}

// anti alias
float smoothBoundaryCoverage(float signed_distance, float boundary_width) {
  return 1.0 - smoothstep(0.0, 1.0, signed_distance / boundary_width + 0.5);
}

// view transform with aspect ratio preserved
mat3 invViewTransform(vec2 center, float scale_y) {
  vec2 Res = iResolution.xy;
  vec2 size = vec2(scale_y * Res.x / Res.y, scale_y);
  vec2 a = center - size / 2.0;
  float Sy = scale_y / Res.y;
  mat3 xform = mat3(
       Sy,   0,   0,
        0,  Sy,   0,
      a.x, a.y, 1.0
  );
  return xform;
}


//
// Main
//

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  mat3 inv_view_xform = invViewTransform(vec2(0.5, 0.5), SCALE);
  float inv_view_scale = inv_view_xform[0][0];

  vec2 uv = vec2(inv_view_xform * vec3(frag_coord, 1.0));
  float t = SCALE_TIME * iTime;

  vec3 color;
  {
    // Draw checker
    float sd = signedDistanceToChecker(uv, CHECKER_SCALE);
    float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
    color = mix(CHECKER_COLOR0, CHECKER_COLOR1, coverage);
  }
  {
    // Prepare random 3 points
    vec2 ps[3];
    for (int i = 0; i <= 2; i++) {
      ps[i] = someNoise(float(i), t);
    }

    // Draw circumcircle
    if (USE_IN_CIRCLE_TEST) {
      float volume = inCircleTestVolume(uv, ps[0], ps[1], ps[2]);
      volume *= IN_CIRCLE_TEST_VOLUME_SCALE;
      float coverage = 1.0 - smoothstep(-1.0, 1.0, volume);
      color = mix(color, DISK_COLOR, DISK_ALPHA * coverage);

    } else {
      vec2 center = circumcircleCenter(ps[0], ps[1], ps[2]);
      float radius = distance(center, ps[0]);
      float sd = signedDistanceToCircle(uv, center, radius);

      float signed_area = cross(vec3(ps[1] - ps[0], 0.0), vec3(ps[2] - ps[0], 0.0)).z;
      sd *= sign(signed_area);

      float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
      color = mix(color, DISK_COLOR, DISK_ALPHA * coverage);
    }

    // Draw triangle
    {
      float sd = signedDistanceToTriangle(uv, ps[0], ps[1], ps[2]);
      float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
      color = mix(color, TRIANGLE_COLOR, TRIANGLE_ALPHA * coverage);
    }

    // Draw point
    {
      float min_distance = 1000.0;
      for (int i = 0; i <= 2; i++) {
        min_distance = min(min_distance, distance(ps[i], uv));
      }
      float coverage = smoothBoundaryCoverage(
          min_distance / inv_view_scale - POINT_RADIUS, AA);
      color = mix(color, POINT_COLOR, coverage);
    }
  }

  frag_color = vec4(color, 1.0);
}
