//
// Mouse interaction
//

vec3 COLOR_INITIAL   = vec3(0.9, 0.9, 0.8);
vec3 COLOR_ACTIVATED = vec3(0.8, 0.9, 0.9);
vec3 COLOR_DOWN      = vec3(0.9, 0.8, 0.9);
vec3 COLOR_CLICK_POS = vec3(0.0);
vec3 COLOR_DOWN_POS  = vec3(1.0);

float CLICK_POS_RADIUS_PX = 18.0;
float DOWN_POW_RADIUS_PX = 12.0;
float AA_PX = 2.0;

float smoothCoverage(float signed_distance, float width) {
  return 1.0 - smoothstep(0.0, 1.0, signed_distance / width + 0.5);
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  bool mouse_activated = iMouse.x > 0.5;
  bool mouse_down = iMouse.z > 0.5;
  vec2 last_mouse_click_pos = abs(iMouse.zw) + vec2(0.5);
  vec2 last_mouse_down_pos = iMouse.xy + vec2(0.5);

  // Clear color
  vec3 color = mouse_down      ? COLOR_DOWN      :
               mouse_activated ? COLOR_ACTIVATED :
                                 COLOR_INITIAL   ;

  // (Last) mouse click position (initially (0, 0))
  {
    float d = distance(last_mouse_click_pos, frag_coord);
    float coverage = smoothCoverage(d - CLICK_POS_RADIUS_PX, AA_PX);
    color = mix(color, COLOR_CLICK_POS, coverage);
  }

  // (Last) mouse down position (initially (0, 0))
  {
    float d = distance(last_mouse_down_pos, frag_coord);
    float coverage = smoothCoverage(d - DOWN_POW_RADIUS_PX, AA_PX);
    color = mix(color, COLOR_DOWN_POS, coverage);
  }

  frag_color = vec4(color, 1.0);
}
