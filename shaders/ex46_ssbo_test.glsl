//
// Test SSBO configuration
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: inline
      data: "array('f', [0, 1, 1, 1])"
  - type: ssbo
    params:
      binding: 1
      type: file
      data: shaders/data/ssbo_test00.bin

samplers: []

programs:
  - name: mainImage
    output: $default
    samplers: []

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

layout (std140, binding = 0) buffer MyBlock0 {
  vec4 b_data0[];
};

layout (std430, binding = 1) buffer MyBlock1 {
  vec4 b_data1[];
};
const ivec2 kSize = ivec2(256);

void mainImage(out vec4 frag_color, in vec2 frag_coord){
  {
    frag_color = b_data0[0];
  }

  {
    ivec2 p = ivec2(frag_coord) % kSize;
    int idx = kSize.x * p.y + p.x;
    frag_color = b_data1[idx];
  }
}
