//
// Anti alias by smoothing boundary coverage
//

float M_PI = 3.14159;
float SCALE_TIME = 0.01;

// length in window space
float AA_WIDTH = 2.0;
float POINT_RADIUS = 16.0;

// NOTE: arguments (b, d, w) must have length unit in the same coordinate system.
// b: boundary where p < b is interior
// d: distance
// w: width of smooth step
float getSmoothBoundaryCoverage(float b, float d, float w) {
  // Derived from: 1.0 - smoothstep(b - w / 2, b + w / 2, d);
  return 1.0 - smoothstep(0.0, 1.0, (d - b) / w + 0.5);
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // Define coordinate
  float inv_xform_scale = 1 / iResolution.y;
  vec2 uv =  inv_xform_scale * frag_coord;

  // Define point
  float t = mod(SCALE_TIME * iTime, 1.0);
  vec2 p = vec2(t, (0.5 + 0.5 * sin(2.0 * M_PI * t)));

  // Gray based on distance
  float d = distance(p, uv);
  float s = inv_xform_scale;
  float coverage = getSmoothBoundaryCoverage(s * POINT_RADIUS, d, s * AA_WIDTH);

  // Final color
  frag_color = vec4(vec3(coverage), 1.0);
}
