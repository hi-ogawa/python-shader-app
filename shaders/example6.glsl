//
// 3d noise projected to 2d
//
// - [x] smoothness proof (by the same token as 2d case)
// - [x] derive upper/lower bound (2 / sqrt(3) ~= 1.15)
// - [x] 3d unit vector sampling
//

float M_PI = 3.1415;

float SCALE_TIME = 0.25;
float SCALE = 4.0;
float NUM_OCTAVES = 3.0;


// R -> [0, 1)
float hash11(float t) {
  return fract(sin(t * 56789) * 56789);
}

// R^2 -> [0, 1)
float hash21(vec2 uv) {
  return hash11(hash11(uv[0]) + 2.0 * hash11(uv[1]));
}

// R^3 -> [0, 1)
float hash31(vec3 v) {
  return hash11(hash11(v[0]) + 2.0 * hash11(v[1]) + 3.0 * hash11(v[2]));
}

// R^4 -> [0, 1)
float hash41(vec4 v) {
  return hash11(hash11(v[0]) + 2.0 * hash11(v[1]) + 3.0 * hash11(v[2]) + 4.0 * hash11(v[3]));
}

// R^3 -> [0, 1)^2
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

// R^3 -> [0, 1)
float gradientNoise3(vec3 v) {
  vec3 vi = floor(v);
  vec3 g000 = hashGradient3(vi + vec3(0.0, 0.0, 0.0));
  vec3 g100 = hashGradient3(vi + vec3(1.0, 0.0, 0.0));
  vec3 g010 = hashGradient3(vi + vec3(0.0, 1.0, 0.0));
  vec3 g110 = hashGradient3(vi + vec3(1.0, 1.0, 0.0));
  vec3 g001 = hashGradient3(vi + vec3(0.0, 0.0, 1.0));
  vec3 g101 = hashGradient3(vi + vec3(1.0, 0.0, 1.0));
  vec3 g011 = hashGradient3(vi + vec3(0.0, 1.0, 1.0));
  vec3 g111 = hashGradient3(vi + vec3(1.0, 1.0, 1.0));

  vec3 vf = v - vi;
  float f000 = dot(g000, vf - vec3(0.0, 0.0, 0.0));
  float f100 = dot(g100, vf - vec3(1.0, 0.0, 0.0));
  float f010 = dot(g010, vf - vec3(0.0, 1.0, 0.0));
  float f110 = dot(g110, vf - vec3(1.0, 1.0, 0.0));
  float f001 = dot(g001, vf - vec3(0.0, 0.0, 1.0));
  float f101 = dot(g101, vf - vec3(1.0, 0.0, 1.0));
  float f011 = dot(g011, vf - vec3(0.0, 1.0, 1.0));
  float f111 = dot(g111, vf - vec3(1.0, 1.0, 1.0));

  vec3 vf_smooth = smoothstep(vec3(0.0), vec3(1.0), vf);
  float t = mix3(f000, f100, f010, f110, f001, f101, f011, f111, vf_smooth);

  // Normalize via upper/lower bound = +- 2 / sqrt(3) ~= 1.15
  // but this is probably provably squashing distribution too much.
  // So, certain tonemap is required for this output
  return (t / 1.15 + 1.0) * 0.5;
}

float noise(vec3 v) {
  float result = 0.0;
  for (float i = 0.0; i < NUM_OCTAVES; i++) {
    float p = pow(2.0, i);
    result += (gradientNoise3(v * p) / p);
  }
  result /= (pow(2.0, NUM_OCTAVES) - 1.0) / (pow(2.0, NUM_OCTAVES - 1.0));
  return result;
}

float tonemap(float fac) {
  return smoothstep(0.3, 0.7, fac);
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv =  SCALE * frag_coord / iResolution.y;
  float fac = tonemap(noise(vec3(uv, SCALE_TIME * iTime)));
  frag_color = vec4(vec3(fac), 1.0);
}
