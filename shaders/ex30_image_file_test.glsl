//
// Image file test
//

/*
%%config-start%%
samplers:
  - name: tex
    type: file
    file: shaders/images/shadertoy/texture_abstract_1.jpg
    mipmap: true
    wrap: repeat
    filter: linear

programs:
  - name: mainImage
    output: $default
    samplers: [tex]

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

void mainImage(out vec4 frag_color, vec2 frag_coord, sampler2D tex) {
  vec2 uv = frag_coord / iResolution.xy * 2.0;
  frag_color = texture(tex, uv);
}
