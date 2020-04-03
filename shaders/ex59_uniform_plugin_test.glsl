//
// UniformPlugin test
//

/*
%%config-start%%
plugins:
  - type: uniform
    params:
      name: U_p0
      default: 0
      min: -1
      max: 2
  - type: uniform
    params:
      name: U_p1
      default: 1
      min: -1
      max: 2

samplers: []
programs:
  - name: mainImage
    samplers: []
    output: $default

offscreen_option:
  fps: 60
  num_frames: 2
%%config-end%%
*/

#ifdef COMPILE_mainImage
  uniform float U_p0 = 0.0;
  uniform float U_p1 = 1.0;

  vec3 makeColor(float t, float p0, float p1) {
    vec3 v = vec3(0.0, 1.0, 2.0) / 3.0;
    vec3 c = 0.5 + 0.5 * cos(2.0 * 3.141592 * (t - v));
    return smoothstep(vec3(p0), vec3(p1), c);
  }

  void mainImage(out vec4 frag_color, vec2 frag_coord) {
    float x = frag_coord.x / iResolution.x;
    vec3 color = makeColor(x, U_p0, U_p1);
    frag_color = vec4(color, 1.0);
  }
#endif
