//
// MultiPass example
//

/*
%%config-start%%
samplers:
  - name: fb
    type: framebuffer

programs:
  - name: mainImage2
    output: fb
    samplers:
      - fb

  - name: mainImage1
    output: $default
    samplers:
      - fb

offscreen_option:
  fps: 60
  num_frames: 422
%%config-end%%
*/

void mainImage1(out vec4 frag_color, vec2 frag_coord, sampler2D fb) {
  frag_color = texelFetch(fb, ivec2(floor(frag_coord)), 0);
}

void mainImage2(out vec4 frag_color, vec2 frag_coord, sampler2D fb) {
  // Initialize fb as white
  if (iFrame == 0) {
    frag_color = vec4(1.0);
    return;
  }

  // Update only each 60 frames
  if (iFrame % 60 != 0) {
    frag_color = texelFetch(fb, ivec2(floor(frag_coord)), 0);
    return;
  }

  frag_color = vec4(vec3(0.0), 1.0);
  int W = int(iResolution.x);
  int H = int(iResolution.y);

  ivec2 us[3] = ivec2[3](ivec2(0, 0), ivec2(W - 1, 0), ivec2(0, H - 1));
  for (int i = 0; i < 3; i++) {
    ivec2 v = 2 * ivec2(floor(frag_coord)) - us[i];
    if (0 <= v.x && v.x < W && 0 <= v.y && v.y < H) {
      vec4 color = texelFetch(fb, v, 0);
      if (color.x > 0.5) {
        frag_color = vec4(1.0);
        return;
      }
    }
  }
}

/*
For shadertoy,

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  mainImage1(frag_color, frag_coord, iChannel0);
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  mainImage2(frag_color, frag_coord, iChannel0);
}
*/
