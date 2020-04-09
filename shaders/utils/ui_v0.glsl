// require: [transform_v0.glsl]

void UI_getMouseState(
    vec4 mouse, out bool activated, out bool down,
    out vec2 last_click_pos, out vec2 last_down_pos) {
  activated = mouse.x > 0.5;
  down = mouse.z > 0.5;
  last_click_pos = abs(mouse.zw) + vec2(0.5);
  last_down_pos = mouse.xy + vec2(0.5);
}

void UI_getMouseDetail(
    vec4 mouse,
    inout bool State_mouse_down, inout vec2 State_mouse_down_p, inout vec2 State_mouse_click_p,
    out bool clicked, out bool moved, out bool released, out vec2 move_delta) {

  bool mouse_activated, mouse_down;
  vec2 last_click_pos, last_down_pos;
  UI_getMouseState(mouse, mouse_activated, mouse_down, last_click_pos, last_down_pos);

  clicked = mouse_down && !all(equal(State_mouse_click_p, last_click_pos));
  moved = !clicked && mouse_down && !(all(equal(State_mouse_down_p, last_down_pos)));
  released = State_mouse_down && !mouse_down;
  move_delta = vec2(0.0);

  State_mouse_down = mouse_down;
  if (clicked) {
    State_mouse_click_p = State_mouse_down_p = last_click_pos;
  }
  if (moved) {
    move_delta = last_down_pos - State_mouse_down_p;
    State_mouse_down_p = last_down_pos;
  }
}

void UI_updateOrbitCamera(
    int control_type, vec2 delta,
    inout mat4 camera_xform, inout vec3 lookat_p) {
  // assert camera_xform in Euclidian group (i.e. no scale factor)
  vec3 T = vec3(camera_xform[3]);
  vec3 X = vec3(camera_xform[0]);
  vec3 Y = vec3(camera_xform[1]);
  // vec3 Z = vec3(camera_xform[2]);
  // assert Z // (T - lookat_p)

  float L = length(T - lookat_p);

  // Orbit
  if (control_type == 0) {
    // when camera is upside-down, we flip "horizontal" orbit direction.
    float upside = sign(dot(Y, vec3(0.0, 1.0, 0.0)));

    mat3 orbit_verti = T_axisAngle(X, delta.y);
    mat3 orbit_horiz = T_rotate3(vec3(0.0, upside * -delta.x, 0.0));

    // NOTE: it's essential to apply `orbit_verti` first (since `X` has to represent instantaneous camera frame's x vector).
    mat4 camera_rel_xform = inverse(T_translate3(lookat_p)) * camera_xform;  // camera frame ralative to lookat_p
    camera_rel_xform = mat4(orbit_horiz * orbit_verti) * camera_rel_xform; // orbit in the frame where lookat_p is origin
    camera_xform = T_translate3(lookat_p) * camera_rel_xform;                // frame back to original
  }

  // Zoom
  if (control_type == 1) {
    camera_xform = camera_xform * T_translate3(vec3(0.0, 0.0, -delta.y));
  }

  // Move (with lookat_p)
  if (control_type == 2) {
    lookat_p += mat3(camera_xform) * vec3(-delta, 0.0);
    camera_xform = camera_xform * T_translate3(vec3(-delta, 0.0));
  }
}


// Return true on interaction
bool UI_handleCameraInteraction(
    vec2 resolution, vec4 mouse, uint key_modifiers,
    vec3 init_camera_p, vec3 init_lookat_p,
    inout bool state_mouse_down,
    inout vec2 state_mouse_down_p,
    inout vec2 state_mouse_click_p,
    inout mat4 state_camera_xform,
    inout vec3 state_lookat_p) {
  bool key_shift   = bool(key_modifiers & 0x02000000u);
  bool key_control = bool(key_modifiers & 0x04000000u);
  bool key_alt     = bool(key_modifiers & 0x08000000u);

  bool initialize = key_alt || all(equal(state_camera_xform[0], vec4(0.0)));
  if (initialize) {
    state_lookat_p = init_lookat_p;
    state_camera_xform = T_lookAt(
        init_camera_p, init_lookat_p, vec3(0.0, 1.0, 0.0));
    return true;
  }

  bool clicked, moved, released;
  vec2 mouse_delta;
  UI_getMouseDetail(
      mouse, /*inout*/ state_mouse_down, state_mouse_down_p, state_mouse_click_p,
      /*out*/ clicked, moved, released, mouse_delta);

  if (mouse_delta.x != 0.0 || mouse_delta.y != 0.0) {
    vec2 delta = mouse_delta / resolution;
    if (key_control) {
      delta *= 4.0;
      UI_updateOrbitCamera(1, delta, state_camera_xform, state_lookat_p);
    } else if (key_shift) {
      UI_updateOrbitCamera(2, delta, state_camera_xform, state_lookat_p);
    } else {
      delta *= M_PI * vec2(2.0, 1.0);
      UI_updateOrbitCamera(0, delta, state_camera_xform, state_lookat_p);
    }
  }

  return clicked || moved;
}


bool UI_interactInvViewXform(
    vec2 resolution, vec4 mouse, uint key_modifiers,
    inout bool state_mouse_down,
    inout vec2 state_mouse_down_p,
    inout vec2 state_mouse_click_p,
    inout mat3 state_inv_view_xform) {
  bool key_shift   = bool(key_modifiers & 0x02000000u);
  bool key_control = bool(key_modifiers & 0x04000000u);
  bool key_alt     = bool(key_modifiers & 0x08000000u);

  bool clicked, moved, released;
  vec2 mouse_delta;
  UI_getMouseDetail(
      mouse, /*inout*/ state_mouse_down, state_mouse_down_p, state_mouse_click_p,
      /*out*/ clicked, moved, released, mouse_delta);

  if (mouse_delta.x != 0.0 || mouse_delta.y != 0.0) {
    if (key_control) {
      // "p"-preserving scale
      vec2 p = state_mouse_click_p;
      float s = 1.0 - mouse_delta.y / 64.0;
      mat3 xform = T_translate2(+ p) * mat3(T_scale2(vec2(s, s))) * T_translate2(- p);
      state_inv_view_xform = state_inv_view_xform * xform;
    }

    if (key_shift) {
      vec2 t = - mouse_delta;
      mat3 xform = T_translate2(t);
      state_inv_view_xform = state_inv_view_xform * xform;
    }
  }
  return clicked || moved;
}
