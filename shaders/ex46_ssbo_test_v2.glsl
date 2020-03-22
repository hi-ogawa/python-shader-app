//
// Test SSBO configuration (various ssbo data alignment)
//

/*
%%config-start%%
plugins:
  - type: ssbo
    params:
      binding: 0
      type: eval
      data: "np.arange(32, dtype=np.uint32)"
  - type: ssbo
    params:
      binding: 1
      type: eval
      data: "np.arange(32, dtype=np.uint32)"
  - type: ssbo
    params:
      binding: 2
      type: eval
      data: "np.arange(32, dtype=np.uint32)"
  - type: ssbo
    params:
      binding: 3
      type: eval
      data: "np.arange(32, dtype=np.uint32)"
  - type: ssbo
    params:
      binding: 4
      type: eval
      data: "np.arange(32, dtype=np.uint32)"
  - type: ssbo
    params:
      binding: 5
      type: eval
      data: "np.arange(32, dtype=np.uint32)"

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

layout (std140, binding = 0) buffer Ssbo0 {
  int Ssbo_140_scalar[];
};

layout (std430, binding = 1) buffer Ssbo1 {
  int Ssbo_430_scalar[];
};

layout (std140, binding = 2) buffer Ssbo2 {
  ivec2 Ssbo_140_vector2[];
};

layout (std430, binding = 3) buffer Ssbo3 {
  ivec2 Ssbo_430_vector2[];
};

layout (std140, binding = 4) buffer Ssbo4 {
  ivec3 Ssbo_140_vector3[];
};

layout (std430, binding = 5) buffer Ssbo5 {
  ivec3 Ssbo_430_vector3[];
};

void mainImage(out vec4 frag_color, in vec2 frag_coord){
  bool test_140_scalar = (Ssbo_140_scalar[0] == 0) && (Ssbo_140_scalar[1] == 4);
  bool test_430_scalar = (Ssbo_430_scalar[0] == 0) && (Ssbo_430_scalar[1] == 1);

  bool test_140_vector2 =
      all(equal(Ssbo_140_vector2[0], ivec2(0, 1))) &&
      all(equal(Ssbo_140_vector2[1], ivec2(4, 5)));

  bool test_430_vector2 =
      all(equal(Ssbo_430_vector2[0], ivec2(0, 1))) &&
      all(equal(Ssbo_430_vector2[1], ivec2(2, 3)));

  bool test_140_vector3 =
      all(equal(Ssbo_140_vector3[0], ivec3(0, 1, 2))) &&
      all(equal(Ssbo_140_vector3[1], ivec3(4, 5, 6)));

  bool test_430_vector3 =
      all(equal(Ssbo_430_vector3[0], ivec3(0, 1, 2))) &&
      all(equal(Ssbo_430_vector3[1], ivec3(4, 5, 6)));

  float fac = 1.0;
  fac *= float(test_140_scalar);
  fac *= float(test_430_scalar);
  fac *= float(test_140_vector2);
  fac *= float(test_430_vector2);
  fac *= float(test_140_vector3);
  fac *= float(test_430_vector3);
  vec3 color = fac * vec3(1.0);
  frag_color = vec4(color, 1.0);
}
