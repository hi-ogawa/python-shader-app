#include "common_v0.glsl"

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  vec2 uv = frag_coord / iResolution.xy;
  float t = uv.x + iTime / 2.0;
  vec3 color;
  {
    // simple cosine + small tweak
    vec3 v1 = vec3(0.0, 1.0 / 3.0, 2.0 / 3.0);
    vec3 rgb; {
      rgb = 0.5 + 0.5 * cos(2.0 * M_PI * (t - v1));
      rgb = smoothstep(vec3(0.0), vec3(1.0), rgb);
      rgb = pow(rgb, vec3(1.0/2.2));
    }
    color = rgb;
  }
  {
    // more tweak points
    vec3 v1 = vec3(0.0, 1.0 / 3.0, 2.0 / 3.0);
    vec3 v2 = vec3(-0.3, -0.1, 0.1);
    vec3 v3 = vec3(0.4, 0.4, 0.4);
    vec3 rgb; {
      rgb = 0.5 + 0.5 * cos(2.0 * M_PI * (t - v1));
      rgb = smoothstep(v2, vec3(1.0), rgb);
      rgb = pow(rgb, v3);
    }
    // color = rgb;
  }
  {
    // Saturated HSV
    t = mod(t, 1.0);
    float h = 2.0;
    float s = 6.0;
    vec3 d3; {
      d3 = abs(t - vec3(0.0, 1.0, 2.0) / 3.0);
      d3 = min(d3, 1.0 - d3);
    }
    vec3 rgb = clamp(h - s * d3, vec3(0.0), vec3(1.0));
    // color = rgb;
  }

  frag_color = vec4(color, 1.0);
}
