//
// #include directive test
//

#include "common_v0.glsl" // M_PI, rotate2

float ORBIT_RADIUS = 0.3;
float DISK_RADIUS_PX = 12.0;
float AA_PX = 3.0;

float smoothCoverage(float signed_distance, float width) {
  return 1.0 - smoothstep(0.0, 1.0, signed_distance / width + 0.5);
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  float inv_view_scale = 1.0 / iResolution.y;
  float AR = iResolution.z;
  vec2 uv = inv_view_scale * frag_coord;

  // Orbiting disk
  vec2 p = rotate2(0.5 * M_PI * iTime) * vec2(ORBIT_RADIUS, 0.0) + vec2(AR, 1.0) * 0.5;
  float sd = distance(uv, p) - inv_view_scale * DISK_RADIUS_PX;
  float fac = smoothCoverage(sd, inv_view_scale * AA_PX);

  frag_color = vec4(vec3(fac), 1.0);
}
