//
// Checker (used as example textures for ex70_mipmap_test.glsl)
//

/*
Usage:
COLOR1="0.3" COLOR2="0.0,1.0,1.0" python -m src.app --width 16 --height 16 shaders/ex71_checker.glsl --offscreen shaders/images/generated/ex71.16.png
COLOR1="0.3" COLOR2="1.0,0.0,1.0" python -m src.app --width 8  --height 8  shaders/ex71_checker.glsl --offscreen shaders/images/generated/ex71.8.png
COLOR1="0.3" COLOR2="1.0,1.0,0.0" python -m src.app --width 4  --height 4  shaders/ex71_checker.glsl --offscreen shaders/images/generated/ex71.4.png
*/

const vec3 kColor1 = vec3(%%ENV:COLOR1:0.0%%);
const vec3 kColor2 = vec3(%%ENV:COLOR2:1.0%%);

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  ivec2 p = ivec2(frag_coord);
  float fac = float((p.x + p.y) % 2);
  vec3 color = mix(kColor1, kColor2, fac);
  frag_color = vec4(color, 1.0);
}
