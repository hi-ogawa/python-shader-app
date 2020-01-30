//
// Nebula
//
// - Thin isosurface of 3d noise as emission source
// - Beer-Lambert model of absorption
//

#define M_PI 3.14159

float SCALE_TIME = 0.15;

// Emission source
float NOISE_SCALE = 3.0;
float NOISE_NUM_OCTAVES = 6.0;
float ISOSURFACE_VALUE_HALF_WIDTH = 0.03;
float NUM_ISOSURFACE_SIDES = 1.0;

// Volume
float VOLUME_DEPTH = 0.2;
float VOLUME_NUM_SAMPLES = 6.0;
float EMISSION_SCALE = 0.2;
vec3 EMISSION_COLOR = vec3(0.0, 1.0, 1.0);


//
// Noise
//

float hash31(vec3 v) {
  vec3 u = vec3(1234.5, 5432.1, 5678.9);
  return fract(sin(dot(v, u) * 2357.0) * 56789.0);
}

float hash41(vec4 v) {
  vec4 u = vec4(1234.5, 5432.1, 5678.9, 3456.7);
  return fract(sin(dot(v, u) * 2357.0) * 56789.0);
}

vec2 hash32(vec3 v) {
  return vec2(hash31(v), hash41(vec4(v, 1.0)));
}

vec3 hashGradient3(vec3 v) {
  vec2 p = hash32(v);

  // Usual spherical sampling
  // Prob([0, theta] \sub [0, pi]) = (1 - cos(theta)) / 2
  float theta = acos(1.0 - 2.0 * p[0]);
  float phi = 2.0 * M_PI * p[1];

  return vec3(
    sin(theta) * cos(phi),
    sin(theta) * sin(phi),
    cos(theta)
  );
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

float gradientNoise3(vec3 v) {
  vec3 vi = floor(v);
  vec3 vf = v - vi;
  float f000 = dot(hashGradient3(vi + vec3(0.0, 0.0, 0.0)), vf - vec3(0.0, 0.0, 0.0));
  float f100 = dot(hashGradient3(vi + vec3(1.0, 0.0, 0.0)), vf - vec3(1.0, 0.0, 0.0));
  float f010 = dot(hashGradient3(vi + vec3(0.0, 1.0, 0.0)), vf - vec3(0.0, 1.0, 0.0));
  float f110 = dot(hashGradient3(vi + vec3(1.0, 1.0, 0.0)), vf - vec3(1.0, 1.0, 0.0));
  float f001 = dot(hashGradient3(vi + vec3(0.0, 0.0, 1.0)), vf - vec3(0.0, 0.0, 1.0));
  float f101 = dot(hashGradient3(vi + vec3(1.0, 0.0, 1.0)), vf - vec3(1.0, 0.0, 1.0));
  float f011 = dot(hashGradient3(vi + vec3(0.0, 1.0, 1.0)), vf - vec3(0.0, 1.0, 1.0));
  float f111 = dot(hashGradient3(vi + vec3(1.0, 1.0, 1.0)), vf - vec3(1.0, 1.0, 1.0));
  vec3 vf_smooth = smoothstep(vec3(0.0), vec3(1.0), vf);
  float t = mix3(f000, f100, f010, f110, f001, f101, f011, f111, vf_smooth);
  // Normalize via upper/lower bound = +- 2 / sqrt(3) ~= 1.15
  return (t / 1.15 + 1.0) * 0.5;
}

float noise(vec3 v, float n) {
  float result = 0.0;
  for (float i = 0.0; i < n; i++) {
    float p = pow(2.0, i);
    result += (gradientNoise3(v * p) / p);
  }
  result /= (pow(2.0, n) - 1.0) / (pow(2.0, n - 1.0));
  return result;
}

//
// Misc
//

float smoothBump(float fac, float bump, float half_width) {
  return 1.0 - smoothstep(0.0, half_width, abs(fac - bump));
}

//
// Main
//

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv =  frag_coord / iResolution.y;
  float t = SCALE_TIME * iTime;

  // Compute "intensity" by summing each layers
  float fac_total = 0.0;
  for (float i = 0.0; i < VOLUME_NUM_SAMPLES; i++) {
    float z = i / VOLUME_NUM_SAMPLES * VOLUME_DEPTH;

    // Noise
    float fac_noise = noise(vec3(NOISE_SCALE * uv, z + t), NOISE_NUM_OCTAVES);
    fac_noise = smoothstep(0.0, 1.0, fac_noise); // tonemap

    // Pickup isosurfaces
    float fac = 0.0;
    fac += smoothBump(fac_noise, 0.5, ISOSURFACE_VALUE_HALF_WIDTH);
    for (float j = 1.0; j <= NUM_ISOSURFACE_SIDES; j++) {
      fac += smoothBump(fac_noise, 0.5 + 4.0 * j * ISOSURFACE_VALUE_HALF_WIDTH, ISOSURFACE_VALUE_HALF_WIDTH);
      fac += smoothBump(fac_noise, 0.5 - 4.0 * j * ISOSURFACE_VALUE_HALF_WIDTH, ISOSURFACE_VALUE_HALF_WIDTH);
    }

    // Attenuate by depth
    fac_total += exp(- z) * fac;
  }

  frag_color = vec4(fac_total * EMISSION_SCALE * EMISSION_COLOR, 1.0);
}
