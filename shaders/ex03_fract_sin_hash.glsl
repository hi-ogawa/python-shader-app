//
// cheap 2d hash
//

// R -> [0, 1)
float hash11(float t) {
  return fract(sin(t * 56789) * 56789);
}

// R^2 -> [0, 1)
float hash21(vec2 uv) {
  return hash11(2.0 * hash11(uv[0]) + hash11(uv[1]));
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv =  (iTime + 1.0) * frag_coord / iResolution.y;
  float fac = hash21(uv);
  frag_color = vec4(vec3(fac), 1.0);
}
