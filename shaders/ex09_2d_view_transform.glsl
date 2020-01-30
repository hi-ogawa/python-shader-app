//
// View coordinate transform
//
// [0, W] x [0, H]  <-->  [   0, W/H] x [ 0, 1]
//                  <-->  [-W/H, W/H] x [-1, 1]
//                  <-->  ...
//
// We can define view transform in various ways e.g.
// - 0. by left-bottom + size (e.g. (0, 0) and (H/W, 1))
// - 1. by center + size      (e.g. (0, 0) and size (2H/W, 2))
// - 2. by aspect ratio preservation constraint +
//   - 2.0. left-bottom + height
//   - 2.1. center + height
// - etc...
//

#define M_PI 3.14159

float SCALE_TIME = 0.1;
float SCALE_CHECKER = 4.0;
vec3 COLOR1 = vec3(0.35);
vec3 COLOR2 = vec3(0.0, 1.0, 1.0);

// 0. left-bottom + size
mat3 invViewTransform(vec2 a, vec2 size) {
  vec2 S = iResolution.xy / size;
  mat3 xform = mat3(
      S.x,   0, 0,
        0, S.y, 0,
      a.x, a.y, 1
  );
  return xform;
}

// 1. center + size
mat3 invViewTransform_Center(vec2 center, vec2 size) {
  vec2 a = center - size / 2.0;
  vec2 S = iResolution.xy / size;
  mat3 xform = mat3(
      S.x,   0, 0,
        0, S.y, 0,
      a.x, a.y, 1
  );
  return xform;
}

// 2.0. left-bottom + size + aspect ratio 1:1
mat3 invViewTransform_AspectRatio(vec2 a, float height) {
  float Sy = height / iResolution.y;
  mat3 xform = mat3(
       Sy,   0, 0,
        0,  Sy, 0,
      a.x, a.y, 1
  );
  return xform;
}

// 2.1. center + size + aspect ratio 1:1
mat3 invViewTransform_AspectRatio_Center(vec2 center, float height) {
  vec2 HW = iResolution.xy;
  vec2 size = vec2(height * HW.x / HW.y, height);
  vec2 a = center - size / 2.0;
  vec2 S = size / HW;
  mat3 xform = mat3(
      S.x,   0, 0,
        0, S.y, 0,
      a.x, a.y, 1
  );
  return xform;
}

bool checker(vec2 uv) {
  return mod(floor(uv.x) + floor(uv.y), 2.0) != 0.0;
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // Define coordinate
  mat3 inv_xform = invViewTransform_AspectRatio_Center(vec2(0.5, 0.5), 1.2);
  vec2 uv = vec2(inv_xform * vec3(frag_coord, 1.0));

  // Checker color
  vec3 color = checker(SCALE_CHECKER * uv) ? COLOR2 : COLOR1;

  // Final color
  frag_color = vec4(color, 1.0);
}
