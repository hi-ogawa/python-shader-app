//
// Standard 3D SDF rendering
//
// NOTE:
//   - OpenGL style coordinate system (i.e. y up, z face)
//   - Surface normal: by definition, grad(SDF) = normal
//   - Ray march convergence analysis:
//     - Simple example: ray marching to a plane with incidence angle t
//       - Writing distances sequence as d(n), then we have
//         d(n+1) = d(n) - d(n) * tan(pi/2 - t)
//                = d(n) (1 - tan(pi/2 - t))
//         i.e. linear convergence with rate of convergence (1 - tan(pi/2 - t)).
//       - When the ray is going away, d(n) diverges with the same rate.
//

#include "common_v0.glsl"

float AA = 2.0;
float SCALE_TIME = 1.0;
bool  DEBUG_NORMAL = true;
bool  DEBUG_NORMAL_CAMERA = false;
bool  CONTROL_CAMERA = true;
bool  CONTROL_CAMERA_PIVOT = true; // Rotate camera "globally" or locally

int   RM_MAX_ITER = 100;
float RM_MAX_DISTANCE = 100.0;
const float RM_SURFACE_DISTANCE = 0.001;
float RM_NORMAL_DELTA = 10.0 * RM_SURFACE_DISTANCE;

float CAMERA_YFOV = 30.0 * M_PI / 180.0;
vec3  CAMERA_LOC =    vec3(1.0, 0.5, 2.0) * 8.0;
vec3  CAMERA_LOOKAT = vec3(0.0);
vec3  CAMERA_UP =     vec3(0.0, 1.0, 0.0);

vec3  CUBE_LOC = vec3(0.0, 0.0, 0.0);
float CUBE_SCALE = 0.8;

bool  CAMERA_ROTATE = true;
vec3  CAMERA_ROTATE_VEC = vec3(0.0, 1.0 / 8.0, 0.0) * 2.0 * M_PI;
bool  CUBE_ROTATE = false;
vec3  CUBE_ROTATE_VEC = vec3(0.0, 1.0 / 4.0, 0.0) * 2.0 * M_PI;

bool  SPHERE_ORBIT = true;
vec3  SPHERE_LOC = vec3(2.0, 0.0, 0.0);
float SPHERE_RADIUS = 0.7;
vec3  SPHERE_ORBIT_VEC = vec3(0.0, 0.0, 1.0 / 4.0) * 2.0 * M_PI;

float LINE_WIDTH = 0.03;


// Box with 6 corners at (+-c.x, +-c.y, +-c.z)
float SDF_box(vec3 p, vec3 c) {
  // [Debug]
  // return distance(p, vec3(0.0)) - 1.0;

  vec3 sd3 = abs(p) - c;
  bool is_inside = all(lessThanEqual(sd3, vec3(0.0)));
  if (is_inside) {
    return max(max(sd3.x, sd3.y), sd3.z);
  }
  vec3 ud3 = clamp(sd3, vec3(0.0), vec3(FLT_MAX));
  return length(ud3);
}

float SDF_sphere(vec3 p, float r) {
  return length(p) - r;
}

float SDF_plane(vec3 p, vec3 normal) {
  return dot(p, normal);
}

float SDF_line(vec3 p, vec3 v, float width) {
  return length(cross(p, v)) - width;
}

float SDF_xyGridPlane(vec3 p, float width) {
  vec2 q = fract(p.xz) ;
  float t = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y));
  return length(vec2(p.y, t)) - width;
}

float SDF_main(vec3 p) {
  float sd = FLT_MAX;

  // [Debug]
  // return length(p) - 1.0;

  // Cube
  {
    mat4 cube_xform = mat4(1.0);
    if (CUBE_ROTATE) {
      vec3 rotv = iTime * CUBE_ROTATE_VEC;
      cube_xform = mat4(rotate3(rotv)) * cube_xform;
    }
    cube_xform = translate3(CUBE_LOC) * cube_xform;

    vec3 p_in_obj = vec3(inverse(cube_xform) * vec4(p, 1.0));
    float sd_cube = SDF_box(p_in_obj / CUBE_SCALE, vec3(1.0)) * CUBE_SCALE;
    sd = min(sd, sd_cube);
  }

  // Sphere
  {
    vec3 center = SPHERE_LOC;
    if (SPHERE_ORBIT) {
      vec3 rotv = iTime * SPHERE_ORBIT_VEC;
      center = rotate3(rotv) * center;
    }
    float sd_sphere = SDF_sphere(p - center, SPHERE_RADIUS);
    sd = min(sd, sd_sphere);
  }

  // Ground
  // sd = min(sd, SDF_plane(p, vec3(0.0, 1.0, 0.0)));

  // Axes
  sd = min(sd, SDF_line(p, vec3(0.0, 1.0, 0.0), LINE_WIDTH));

  // Grid plane
  sd = min(sd, SDF_xyGridPlane(p, LINE_WIDTH));

  return sd;
}

float rayMarch(vec3 orig, vec3 dir) {
  float t = 0.0;
  for (int i = 0; i < RM_MAX_ITER; i++) {
    float sd = SDF_main(orig + t * dir);
    t += sd;
    if (sd < 0.0 || t >= RM_MAX_DISTANCE) {
      return RM_MAX_DISTANCE;
    }
    if (sd < RM_SURFACE_DISTANCE) {
      return t;
    }
  }
  return RM_MAX_DISTANCE;
}


//
// Misc
//

// [0, W] x [0, H]  -->  [-X/2, X/2] x [-tan(yfov/2), tan(yfov/2)]
// s.t. aspect ratio preserved
mat3 invViewTransform(float yfov) {
  float W = iResolution.x;
  float H = iResolution.y;
  float AR = W / H;
  float HALF_Y = tan(yfov / 2.0);
  float HALF_X = AR * HALF_Y;
  vec2 a = vec2(-HALF_X, -HALF_Y);
  float Sy = (2.0 * HALF_Y) / H;
  mat3 xform = mat3(
       Sy, 0.0, 0.0,
      0.0,  Sy, 0.0,
      a.x, a.y, 1.0);
  return xform;
}

mat4 lookatTransform(vec3 loc, vec3 lookat_loc, vec3 up) {
  vec3 z = normalize(loc - lookat_loc);
  vec3 x = - cross(z, up);
  vec3 y = cross(z, x);
  mat4 xform = mat4(
      x,   0.0,
      y,   0.0,
      z,   0.0,
      loc, 1.0);
  return xform;
}


//
// Main
//

vec3 singleSample(vec2 frag_coord, mat3 inv_view_xform, mat4 camera_xform) {
  // Setup camera ray
  vec3 ray_orig = vec3(camera_xform[3]);
  vec3 ray_dir; {
    vec2 uv = vec2(inv_view_xform * vec3(frag_coord, 1.0));
    vec3 ray_pos = mat3(camera_xform) * vec3(uv, -1.0);
    ray_dir = normalize(ray_pos);
  }

  // RayMarch scene
  vec3 color = vec3(0.0);
  float d = rayMarch(ray_orig, ray_dir);
  if (d < RM_MAX_DISTANCE) {
    color = vec3(1.0);

    // Approximate <face normal> = grad(SDF) by finite difference.
    vec3 p = ray_orig + d * ray_dir;
    float dx_sdf = SDF_main(p + RM_NORMAL_DELTA * vec3(1.0, 0.0, 0.0)) / RM_NORMAL_DELTA;
    float dy_sdf = SDF_main(p + RM_NORMAL_DELTA * vec3(0.0, 1.0, 0.0)) / RM_NORMAL_DELTA;
    float dz_sdf = SDF_main(p + RM_NORMAL_DELTA * vec3(0.0, 0.0, 1.0)) / RM_NORMAL_DELTA;
    vec3 normal = vec3(dx_sdf, dy_sdf, dz_sdf);
    vec3 normal_camera_sp = inverse(mat3(camera_xform)) * normal;

    // [Debug] normal
    if (DEBUG_NORMAL) {
      vec3 n = DEBUG_NORMAL_CAMERA ? normal_camera_sp : normal;
      color = (0.5 + 0.5 * n);
    }
  }
  return color;
}

mat4 getCameraTransform(vec4 mouse, vec2 resolution) {
  bool mouse_activated, mouse_down;
  vec2 last_click_pos, last_down_pos;
  getMouseStatus(mouse, mouse_activated, mouse_down, last_click_pos, last_down_pos);

  mat4 default_camera_xform = lookatTransform(CAMERA_LOC, CAMERA_LOOKAT, CAMERA_UP);
  if (!(mouse_activated && mouse_down)) {
    return default_camera_xform;
  }

  mat4 camera_xform = mat4(1.0);
  vec2 delta = (last_down_pos - last_click_pos) / resolution;
  delta *= 2.0 * M_PI;

  if (CONTROL_CAMERA_PIVOT) {
    // Compute "origin-pivot" camera xform in two steps
    vec3 roty = vec3(0.0, -delta.x, 0.0);
    vec3 camera_loc = rotate3(roty) * CAMERA_LOC;
    mat4 camera_xform_tmp = lookatTransform(camera_loc, CAMERA_LOOKAT, CAMERA_UP);

    vec3 rotx_axis = vec3(camera_xform_tmp[0]);
    float rotx_angle = delta.y;
    mat3 rotx = axisAngleTransform(rotx_axis, rotx_angle);
    camera_xform = mat4(rotx) * camera_xform_tmp;

  } else {
    // Rotate camera locally with keeping "camera up"
    mat3 rot_local = mat3(1.0)
        * rotate3(vec3(    0.0, -delta.x, 0.0))
        * mat3(default_camera_xform)
        * rotate3(vec3(delta.y,      0.0, 0.0));
    camera_xform = translate3(CAMERA_LOC) * mat4(rot_local);
  }

  return camera_xform;
}

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  // Setup coordinate system
  mat3 inv_view_xform = invViewTransform(CAMERA_YFOV);
  mat4 camera_xform = mat4(1.0);
  {
    if (CONTROL_CAMERA) {
      camera_xform = getCameraTransform(iMouse, iResolution.xy);

    } else if (CAMERA_ROTATE) {
      vec3 camera_loc = rotate3(CAMERA_ROTATE_VEC * iTime) * CAMERA_LOC;
      camera_xform = lookatTransform(camera_loc, CAMERA_LOOKAT, CAMERA_UP);
    }
  }

  // Averaging multisamples
  vec3 color = vec3(0.0);
  vec2 int_coord = floor(frag_coord);
  for (float i = 0.0; i < AA; i++) {
    for (float j = 0.0; j < AA; j++) {
      vec2 fract_coord = (1.0 + vec2(i, j) / 2.0) / AA;
      vec2 ms_frag_coord = int_coord + fract_coord;
      color += singleSample(ms_frag_coord, inv_view_xform, camera_xform);
    }
  }
  color /= (AA * AA);
  frag_color = vec4(color, 1.0);
}
