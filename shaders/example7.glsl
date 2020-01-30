//
// Voronoi diagram with noise points
// TODO:
// - anti alias cell boundary by computing cell boundary coveragy
//

#define M_PI 3.14159

float SCALE = 5.0;
float SCALE_TIME = 1.0;

float POINT_RADIUS = 4.0;
float GRID_LINE_WIDTH = 1.0;

vec3 CLEAR_COLOR = vec3(0.15);
vec3 POINT_COLOR = vec3(0.0, 1.0, 1.0);
vec3 GRID_LINE_COLOR = vec3(0.3);

float AA = 2.0;

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

float hash41(vec4 v) {
  return hash11(hash11(v[0]) + 2.0 * hash11(v[1]) + 3.0 * hash11(v[2]) + 4.0 * hash11(v[3]));
}

vec2 hash22(vec2 v) {
  return vec2(hash21(v), hash31(vec3(v, 1.0)));
}

vec2 hash32(vec3 v) {
  return vec2(hash31(v), hash41(vec4(v, 1.0)));
}

vec3 hash23(vec2 v) {
  return vec3(hash21(v), hash32(vec3(v, 1.0)));
}

vec4 hash24(vec2 v) {
  return vec4(hash32(vec3(v, 0.0)), hash32(vec3(v, 1.0)));
}

vec2 unitVector2(float t) {
  return vec2(cos(2.0 * M_PI * t), sin(2.0 * M_PI * t));
}

vec2 hashGradient2(vec2 uv) {
  return unitVector2(hash21(uv));
}

float mix2(float f00, float f10, float f01, float f11, vec2 uv) {
  return mix(mix(f00, f10, uv[0]), mix(f01, f11, uv[0]), uv[1]);
}

float mix3(
    float f000, float f100, float f010, float f110,
    float f001, float f101, float f011, float f111,
    vec3 v) {
  float fxy0 = mix2(f000, f100, f010, f110, v.xy);
  float fxy1 = mix2(f001, f101, f011, f111, v.xy);
  return mix(fxy0, fxy1, v.z);
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

vec2 noisePointOffset2(vec2 fixed_seed, float conti_seed) {
  // Taking hashed direction to break inherent velocity pattern of gradientNoise2
  vec4 p = hash24(fixed_seed);
  vec2 q = vec2(p[0], p[1]);
  vec2 dir1 = unitVector2(p[2]);
  vec2 dir2 = unitVector2(p[3]);
  vec2 v = vec2(
      gradientNoise2(q +     0.0 + conti_seed * dir1),
      gradientNoise2(q + 12345.0 + conti_seed * dir2));

  // Tonemap [0, 1] to make movement more "dynamical"
  return smoothstep(0.0, 1.0, v);
}

//
// Voronoi diagram
//

void distanceToVoronoiSite(
    vec2 uv, float noise_seed,
    out float min_distance, out vec2 cell_index) {
  min_distance = sqrt(2);
  for (float i = -1.0; i <= 1.0; i++) {
    for (float j = -1.0; j <= 1.0; j++) {
      vec2 lattice_uv = floor(uv + vec2(i, j));
      vec2 voronoi_uv = lattice_uv + noisePointOffset2(lattice_uv, noise_seed);
      float current_distance = distance(uv, voronoi_uv);
      if (current_distance < min_distance) {
        min_distance = current_distance;
        cell_index = lattice_uv;
      }
    }
  }
}

//
// Misc
//

// grid
float distanceToGrid(vec2 uv) {
  vec2 uvf = fract(uv);
  return min(min(min(uvf.x, uvf.y), 1 - uvf.x), 1 - uvf.y);
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
    float coverage = smoothBoundaryCoverage(GRID_LINE_WIDTH, d / inv_view_scale, AA);
    color = mix(color, GRID_LINE_COLOR, coverage);
  }
  {
    float site_distance;
    vec2 cell_index;
    distanceToVoronoiSite(uv, t, site_distance, cell_index);
    float coverage = smoothBoundaryCoverage(POINT_RADIUS, site_distance / inv_view_scale, AA);
    vec3 voronoi_cell_color = hash23(cell_index);

    color = mix(color, voronoi_cell_color, 0.70);
    color = mix(color, POINT_COLOR, coverage);
  }

  frag_color = vec4(color, 1.0);
}
