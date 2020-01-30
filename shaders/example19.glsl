//
// #include directive test
//

#include "common_v0.glsl"

float CHECKER_SCALE = 4.0;
vec3  CHECKER_COLOR1 = vec3(1.0) * 0.30;
vec3  CHECKER_COLOR2 = vec3(0.0, 1.0, 1.0);

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv = frag_coord / iResolution.y;
  float fac = float(checker_bool(CHECKER_SCALE * uv));
  vec3 color = mix(CHECKER_COLOR1, CHECKER_COLOR2, fac);
  frag_color = vec4(color, 1.0);
}
