// require: [math_v0.glsl, transform_v0.glsl]

void Sampling_hemisphereCosine(vec2 u, out vec3 p, out float pdf) {
  float phi = 2.0 * M_PI * u.y;
  float theta = 0.5 * acos(1.0 - 2.0 * u.x);  // P(t) ~ sin(t)cos(t),  F(t) = (1 - cos(2t)) / 2
  p = T_sphericalToCartesian(vec3(1.0, theta, phi));
  pdf = cos(theta) / M_PI;
}

void Sampling_hemisphereUniform(vec2 u, out vec3 p, out float pdf) {
  float phi = 2.0 * M_PI * u.y;
  float theta = acos(1.0 - u.x);  // P(t) ~ sin(t),  F(t) = 1 - cos(t)
  p = T_sphericalToCartesian(vec3(1.0, theta, phi));
  pdf = 1.0 / (2.0 * M_PI);
}

void Sampling_sphereUniform(vec2 u, out vec3 p, out float pdf) {
  float phi   = 2.0 * M_PI * u.y;
  float theta = acos(1.0 - 2.0 * u.x); // P(t) ~ sin(t),  F(t) = (1 - cos(t)) / 2
  p = T_sphericalToCartesian(vec3(1.0, theta, phi));
  pdf = 1.0 / (4.0 * M_PI);
}
