//
// Delaunay triangulation
//

#define M_PI 3.14159

float SCALE = 5.0;
float SCALE_TIME = .3;

float POINT_RADIUS = 3.0;
float GRID_LINE_WIDTH = 1.0;
float QUAD_EDGE_WIDTH = 3.0;
float TRI_EDGE_WIDTH  = 2.0;

vec3 CLEAR_COLOR = vec3(0.15);
vec3 GRID_LINE_COLOR = vec3(0.3);
vec3 POINT_COLOR = vec3(0.0, 1.0, 1.0);
vec3 QUAD_EDGE_COLOR = vec3(1.0, 0.0, 1.0);
vec3 TRI_EDGE_COLOR  = vec3(1.0, 1.0, 0.0) * 0.8;
float TRI_EDGE_DEGENERACY_FACTOR_SCALE = 0.1; // reduce sudden triangulation flip

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

float hash31(vec3 v) {
  return hash11(hash11(v[0]) + 2.0 * hash11(v[1]) + 3.0 * hash11(v[2]));
}

vec2 hash22(vec2 v) {
  return vec2(hash21(v), hash31(vec3(v, 1.0)));
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

vec2 someNoise(vec2 hash_seed, float conti_seed) {
  // Taking hashed direction to break inherent velocity pattern of gradientNoise2
  vec2 p = hash22(hash_seed);
  vec2 dir1 = unitVector2(p[0]);
  vec2 dir2 = unitVector2(p[1]);
  vec2 v = vec2(
      gradientNoise2(123.456 * hash_seed + 456.789 + conti_seed * dir1),
      gradientNoise2(456.123 * hash_seed + 789.456 + conti_seed * dir2));

  // Tonemap [0, 1] to make movement more "dynamical"
  return smoothstep(0.0, 1.0, v);
}

//
// Delaunay triangulation
//

void distanceToNoiseSitesTriangulation(
    vec2 uv, float noise_seed,
    out float min_distance_vertex,
    out float min_distance_quad_edge,
    out float min_distance_tri_edge,
    out float in_circle_test_det) {

  vec2 lattice_uv = floor(uv);
  min_distance_vertex = sqrt(2.0);
  min_distance_quad_edge = 1.0;
  min_distance_tri_edge = sqrt(2.0);

  // Cache sites coordinate
  vec2 sites[9];
  #define _ENCODE_IJ(i, j)       (3 * int(i + 1.0) + int(j + 1.0))
  #define READ_SITE(i, j)        sites[_ENCODE_IJ(i, j)]
  #define WRITE_SITE(i, j, site) sites[_ENCODE_IJ(i, j)] = site

  // iterate sites
  for (float i = -1.0; i <= 1.0; i++) {
    for (float j = -1.0; j <= 1.0; j++) {
      vec2 lattice_ij = lattice_uv + vec2(i, j);
      vec2 site_ij = lattice_ij + someNoise(lattice_ij, noise_seed);
      min_distance_vertex = min(min_distance_vertex, distance(uv, site_ij));
      WRITE_SITE(i, j, site_ij);
    }
  }

  // iterate quad edges
  // - these quads are not necessarily convex, but the probablity of such case should be quite low.
  //   or you could force convexity by weaking the noise factor (e.g. 0.5 * someNoise(...)).
  for (float k = -1.0; k <= 1.0; k++) {
    for (float l = -1.0; l <= 0.0; l++) {
      float d_kl = distance_Point_LineSegment(uv, READ_SITE(k, l), READ_SITE(k + 0.0, l + 1.0));
      float d_lk = distance_Point_LineSegment(uv, READ_SITE(l, k), READ_SITE(l + 1.0, k + 0.0));
      min_distance_quad_edge = min(min_distance_quad_edge, min(d_kl, d_lk));
    }
  }

  // iterate triangulation diagonal edges
  for (float k = -1.0; k <= 0.0; k++) {
    for (float l = -1.0; l <= 0.0; l++) {
      vec2 v0 = READ_SITE(k + 0.0, l + 0.0);
      vec2 v1 = READ_SITE(k + 1.0, l + 0.0);
      vec2 v2 = READ_SITE(k + 0.0, l + 1.0);
      vec2 v3 = READ_SITE(k + 1.0, l + 1.0);

      // Cf. Guibas 1985, Lemma 8.1 (https://doi.org/10.1145%2F282918.282923)
      mat3 in_circle_test_mat = mat3(
          (v1 - v0).x, (v1 - v0).y, dot(v1, v1) - dot(v0, v0),
          (v2 - v0).x, (v2 - v0).y, dot(v2, v2) - dot(v0, v0),
          (v3 - v0).x, (v3 - v0).y, dot(v3, v3) - dot(v0, v0));
      float in_circle_test_det_current = determinant(in_circle_test_mat);
      float d = in_circle_test_det_current > 0.0
          ? distance_Point_LineSegment(uv, v1, v2)  // edge: 10 <--> 01
          : distance_Point_LineSegment(uv, v0, v3); // edge: 00 <--> 11
      if (d < min_distance_tri_edge) {
        min_distance_tri_edge = d;
        in_circle_test_det = in_circle_test_det_current;
      }
    }
  }

  #undef _ENCODE_IJ
  #undef READ_SITE
  #undef WRITE_SITE
}

//
// Misc
//

// grid
float distanceToGrid(vec2 uv) {
  vec2 uvf = fract(uv);
  return min(min(min(uvf.x, uvf.y), 1.0 - uvf.x), 1.0 - uvf.y);
}

// anti alias
float smoothBoundaryCoverage(float b, float d, float w) {
  return 1.0 - smoothstep(0.0, 1.0, (d - b) / w + 0.5);
}


//
// Main
//

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  float inv_view_scale = SCALE / iResolution.y;
  vec2 uv =  inv_view_scale * frag_coord;
  float t = SCALE_TIME * iTime;

  vec3 color = CLEAR_COLOR;
  {
    float d = distanceToGrid(uv);
    float coverage = smoothBoundaryCoverage(0.5 * GRID_LINE_WIDTH, d / inv_view_scale, AA);
    color = mix(color, GRID_LINE_COLOR, coverage);
  }
  {
    float d_vertex, d_quad_edge, d_tri_edge, in_circle_test_det;
    distanceToNoiseSitesTriangulation(
        uv, t, d_vertex, d_quad_edge, d_tri_edge, in_circle_test_det);

    float coverage_vertex = smoothBoundaryCoverage(
        POINT_RADIUS, d_vertex / inv_view_scale, AA);
    float coverage_quad_edge = smoothBoundaryCoverage(
        0.5 * QUAD_EDGE_WIDTH, d_quad_edge / inv_view_scale, AA);
    float coverage_tri_edge = smoothBoundaryCoverage(
        0.5 * TRI_EDGE_WIDTH, d_tri_edge / inv_view_scale, AA);
    float degeneracy_factor = smoothstep(
        0.0, TRI_EDGE_DEGENERACY_FACTOR_SCALE, abs(in_circle_test_det));

    color = mix(color, QUAD_EDGE_COLOR, coverage_quad_edge);
    color = mix(color, TRI_EDGE_COLOR, coverage_tri_edge * degeneracy_factor);
    color = mix(color, POINT_COLOR, coverage_vertex);
  }

  frag_color = vec4(color, 1.0);
}
