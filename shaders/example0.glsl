float checker(vec2 uv) {
  return float(mod(floor(uv.x) + floor(uv.y), 2.0) == 1.0);
}

vec3 COLOR1 = vec3(1.0) * 0.30;
vec3 COLOR2 = vec3(0.0, 1.0, 1.0);

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv = frag_coord / iResolution.y * 4.0 + iTime;
  float fac = checker(uv);
  vec3 color = mix(COLOR1, COLOR2, fac);
  frag_color = vec4(color, 1.0);
}
