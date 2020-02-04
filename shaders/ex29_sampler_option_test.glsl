//
// Texture/sampler option test and image file test
//

/*
%%config-start%%
samplers:
  - name: fb
    type: framebuffer
    size: [3, 3]   # or $default
    mipmap: true   # or false
    wrap: repeat   # or clamp
    filter: linear # or nearest

programs:
  - name: mainImage2
    output: fb
    samplers: []
  - name: mainImage1
    output: $default
    samplers: [fb]

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

const vec3 OZN = vec3(1.0, 0.0, -1.0);

void mainImage1(out vec4 frag_color, vec2 frag_coord, sampler2D fb) {
  vec2 uv = frag_coord / iResolution.xy * 2.0;
  frag_color = texture(fb, uv);
}

void mainImage2(out vec4 frag_color, vec2 frag_coord) {
  // Write 2x2 checker pixels

  // other pixels are white
  vec3 color = OZN.xxx;

  vec2 uv = floor(frag_coord);
  if ((uv.x == 0.0 && uv.y == 0.0) || (uv.x == 1.0 && uv.y == 1.0)) {
    color = OZN.xyx;
  }
  if ((uv.x == 1.0 && uv.y == 0.0) || (uv.x == 0.0 && uv.y == 1.0)) {
    color = OZN.yxx;
  }

  frag_color = vec4(color, 1.0);
}
