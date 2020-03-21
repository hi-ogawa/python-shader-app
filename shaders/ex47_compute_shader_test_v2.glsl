//
// Test compute shader (support eval mode for size)
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: size
      size: "W * H * 4 * 4"

samplers: []

programs:
  - name: mainCompute
    type: compute
    local_size: [32, 32, 1]
    global_size: "[W, H, 1]"
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

vec3 checker(vec2 uv) {
  vec2 q = sign(fract(uv) - 0.5);
  float fac = (0.5 - 0.5 * q.x * q.y);
  fac = mix(0.25, 0.95, fac);
  return fac * vec3(0.0, 1.0, 1.0);
}

void mainCompute(uvec3 comp_coord, /*unused*/ uvec3 comp_local_coord) {
  ivec2 size = ivec2(iResolution.xy);
  ivec2 p = ivec2(comp_coord);
  int idx = size.x * p.y + p.x;
  if (!all(lessThan(p, size))) { return; }

  vec2 uv = (vec2(p) + 0.5) / iResolution.y;
  b_data[idx] = vec4(checker(2.0 * uv - iTime), 1.0);
}

void mainImage(out vec4 frag_color, vec2 frag_coord){
  ivec2 size = ivec2(iResolution.xy);
  ivec2 p = ivec2(frag_coord);
  int idx = size.x * p.y + p.x;
  frag_color = b_data[idx];
}
