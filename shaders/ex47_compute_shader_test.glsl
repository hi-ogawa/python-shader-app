//
// Test compute shader
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: size
      size: "4 * 4"  # float x 4

samplers: []

programs:
  - name: mainCompute
    type: compute
    local_size: [1, 1, 1]
    global_size: [1, 1, 1]
    samplers: []

  - name: mainImage
    samplers: []
    output: $default

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

layout (std140, binding = 0) buffer MyBlock {
  vec4 b_data[];
};

void mainCompute(uvec3 comp_coord, uvec3 comp_local_coord) {
  float t = iTime / 3.0;
  vec3 v = vec3(0.0, 1.0, 2.0) / 3.0;
  vec3 c = 0.5 + 0.5 * cos(2.0 * 3.14159 * (t - v));
  b_data[0] = vec4(c, 1.0);
}

void mainImage(out vec4 frag_color, in vec2 frag_coord){
  frag_color = b_data[0];
}
