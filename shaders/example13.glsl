//
// 2D Section of Rotating Torus
//

#define M_PI 3.14159

float AA = 2.0;
float SCALE_TIME = 0.6;
vec2  UV_CENTER = vec2(0.0, 0.0);
float UV_HEIGHT = 3.2;

float TORUS_R1 = 1.0;
float TORUS_R2 = 0.35;
vec3  TORUS_ROT_VELOCITY = vec3(M_PI, 0.0, M_PI * 2.5 / 2.0);
vec4  TORUS_COLOR = vec4(vec3(0.95, 1.0, 1.0), 0.8);

float CHECKER_SCALE = 1.0;
vec3  CHECKER_COLOR0 = vec3(0.1);
vec3  CHECKER_COLOR1 = vec3(0.2);


// Torus boundary given by
//   q(u, v) = R_{z, u} (r1 e1 + R_{y, v} (r2 e1))
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

mat4 rotationTransform(vec3 r) {
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
  mat4 R = mat4(Z * Y * X);
  return R;
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
  float t = SCALE_TIME * iTime;

  vec3 color;
  {
    // Checker
    float sd = signedDistanceToChecker(uv, CHECKER_SCALE);
    float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
    color = mix(CHECKER_COLOR0, CHECKER_COLOR1, coverage);
  }
  {
    // Animating Torus
    mat4 torus_xform = rotationTransform(TORUS_ROT_VELOCITY * t);

    // Approximate 2D section distance as 3D distance
    //   this approximation under-estimates distance on 2d section
    //   when 3d closest point's normal is not orthogonal to 2d section.
    //   For example, there will be too much AA blur when torus is tilted.
    vec3 p = vec3(uv, 0.0);
    vec3 p_in_torus = vec3(inverse(torus_xform) * vec4(p, 1.0));
    float sd = signedDistanceToTorus(p_in_torus, TORUS_R1, TORUS_R2);

    float coverage = smoothBoundaryCoverage(sd / inv_view_scale, AA);
    color = mix(color, TORUS_COLOR.xyz, TORUS_COLOR.w * coverage);
  }

  frag_color = vec4(color, 1.0);
}
