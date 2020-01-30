//
// 2D section of Moving/Rotating Tori
//

#define M_PI 3.14159

float AA = 2.0;
float SCALE_TIME = 1.2;
vec2  UV_CENTER = vec2(0.0, 0.0);
float UV_HEIGHT = 4.2;

float CHECKER_SCALE = 1.0;
vec3  CHECKER_COLOR0 = vec3(0.1);
vec3  CHECKER_COLOR1 = vec3(0.2);

float LOOP_INTERVAL = 4.0;

float TORUS_R1 = 1.5;
float TORUS_R2 = 0.5;
vec3  TORUS_LOC_VELOCITY = vec3(0.0, 0.0, -1.0);

vec4 TORUS_COLORS[] = vec4[](
  vec4(1.0, 0.6, 1.0, 0.9),
  vec4(0.6, 1.0, 1.0, 0.9),
  vec4(1.0, 0.6, 1.0, 0.9));

vec3 TORUS_LOC_INITS[] = vec3[](
  vec3(0.0, 0.0, 0.0),
  vec3(0.0, 0.0, 2.0),
  vec3(0.0, 0.0, 4.0));

vec3 TORUS_ROT_INITS[] = vec3[](
  vec3(0.0, M_PI / 2.0, 0.0),
  vec3(M_PI / 2.0, 0.0, 0.0),
  vec3(0.0, M_PI / 2.0, 0.0));

vec3 TORUS_ROT_VELOCITIES[] = vec3[](
  vec3(2.0 * M_PI / LOOP_INTERVAL, 0.0, 0.0),
  vec3(0.0, 0.0, 2.0 * M_PI / LOOP_INTERVAL),
  vec3(2.0 * M_PI / LOOP_INTERVAL, 0.0, 0.0));


// Torus boundary given by
// q(u, v) = R_{z, u} (r1 e1 + R_{y, v} (r2 e1))
float signedDistanceToTorus(vec3 p, float r1, float r2) {
  return length(vec2(length(p.xy) - r1, p.z)) - r2;
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

mat4 translationTransform(vec3 l) {
  return mat4(
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    l.x, l.y, l.z, 1.0);
}

// [0, W] x [0, H]  <-->  [c.x - A, c.x + A] x [c.y - B, c.y + B]
// where AR = W / H
//       A = AR * height / 2
//       B = height / 2
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

// Anti aliasing
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
  float t = mod(SCALE_TIME * iTime, LOOP_INTERVAL);

  vec3 color;
  {
    // Checker
    float sd = signedDistanceToChecker(uv, CHECKER_SCALE);
    float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
    color = mix(CHECKER_COLOR0, CHECKER_COLOR1, coverage);
  }
  {
    // Three Tori
    for (int i = 0; i < 3; i++) {
      // Animate torus
      vec3 torus_loc = TORUS_LOC_VELOCITY * t + TORUS_LOC_INITS[i];
      vec3 torus_rot = TORUS_ROT_VELOCITIES[i] * t + TORUS_ROT_INITS[i];
      mat4 torus_xform = translationTransform(torus_loc) * mat4(rot3(torus_rot));

      // Distance to torus 2d section
      vec3 p = vec3(uv, 0.0);
      vec3 p_in_torus = vec3(inverse(torus_xform) * vec4(p, 1.0));
      float sd = signedDistanceToTorus(p_in_torus, TORUS_R1, TORUS_R2);

      float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
      color = mix(color, TORUS_COLORS[i].xyz, TORUS_COLORS[i].w * coverage);
    }
  }

  frag_color = vec4(color, 1.0);
}
