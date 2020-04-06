// require: [math_v0.glsl]

float Brdf_beckmannG(float mu) {
  // Masking-shadowing function by [3/3] Pade approx.
  float g =
      (0.0 + 42.5770668488687*mu + -2.73558953267639e-13*mu*mu + 3.54808890407244*mu*mu*mu)
      / (16.9857921414919 + 21.2885334244342*mu + 9.90837874920349*mu*mu + 1.77404445203615*mu*mu*mu);
  g = min(1.0, g);
  return g;
}

float Brdf_GGX_D(float n_o_wh, float a2) {
  float D = a2 / (M_PI * pow2(pow2(n_o_wh) * (a2 - 1.0) + 1.0));
  return D;
}

float Brdf_GGX_G2(float n_o_wo, float n_o_wi, float a2) {
  // Lambda = (-1 + sqrt(1 / mu^2 + 1)) / 2
  // mu = 1 / (alpha tan(t))
  // G2 = 1 / (1 + Lambda_o + Lambda_i)
  //    = 2 / ( sqrt(1 / mu_o^2 + 1) + sqrt(1 / mu_i^2 + 1) )
  float G2_tmp1 = sqrt(a2 * (1.0 / pow2(n_o_wo) - 1.0) + 1.0);
  float G2_tmp2 = sqrt(a2 * (1.0 / pow2(n_o_wi) - 1.0) + 1.0);
  float G2 = 2.0 / (G2_tmp1 + G2_tmp2);
  return G2;
}

float Brdf_GGX_Vis(float n_o_wo, float n_o_wi, float wh_o_wo, float wh_o_wi, float a2) {
  // Vis = G2 / 4 (n.wo) (n.wi)
  float Vis_tmp1 = n_o_wi * sqrt(pow2(n_o_wo) * (1.0 - a2) + a2);
  float Vis_tmp2 = n_o_wi * sqrt(pow2(n_o_wi) * (1.0 - a2) + a2);
  float Vis = 0.5 / (Vis_tmp1 + Vis_tmp2);
  return Vis * step(0.0, wh_o_wo) * step(0.0, wh_o_wi);
}

void Brdf_GGX_sampleCosineD(vec2 u, float a, out vec3 wh, out float pdf) {
  float theta = a * sqrt(u.x / (1.0 - u.x));
  float phi = 2.0 * M_PI * u.y;
  wh = T_sphericalToCartesian(vec3(1.0, theta, phi));
  pdf = cos(theta) * Brdf_GGX_D(cos(theta), pow2(a));
}

vec3 Brdf_F_Schlick(float wh_o_wo, vec3 F0) {
  vec3 F = F0 + (1.0 - F0) * pow5(1.0 - wh_o_wo);
  return F;
}

vec3 Brdf_default(
    vec3 wo, vec3 wi, vec3 wh, vec3 n,
    vec3 diffuse_albedo, float beckmann_stddev) {
  //
  // Microfacet specular BRDF (m: half vector)
  //   F(m, wi) D(n, m) G(n, m, wi, wo) / 4 (n.wo) (n.wi)
  //

  // Fresnel equation reflectance (IOR = 1.5) by Schlick's approx
  float F0 = 0.04;  // at dot(wo, wh) = cos(t) = 1
  float F = F0 + (1.0 - F0) * pow5(1.0 - dot(wo, wh));

  // Beckmann surface's slope distribution stddev
  float stddev = beckmann_stddev;

  // Distribution of normal
  float ta = tan(acos(dot(n, wh)));
  float gaussian = exp(- (ta / stddev) * (ta / stddev) / 2) / (sqrt(2.0 * M_PI) * stddev);
  float D = gaussian / pow4(dot(n, wh));

  // Corresponding "height correlated" masking-shadowing function by [3/3] Pade approx.
  float mu_wo = 1.0 / tan(acos(dot(n, wo)));
  float mu_wi = 1.0 / tan(acos(dot(n, wi)));
  float G_wo = Brdf_beckmannG(mu_wo / stddev);
  float G_wi = Brdf_beckmannG(mu_wi / stddev);
  float G2 = (G_wo * G_wi) / (G_wo + G_wi - G_wo * G_wi);

  float brdf_microfacet_spec =
      (F * D * G2 * step(0.0, dot(wh, wo)) * step(0.0, dot(wh, wi)))
      / (4.0 * dot(n, wo) * dot(n, wi));

  //
  // Lambertian diffuse BRDF
  //
  vec3 brdf_diffuse = diffuse_albedo / M_PI;

  // Mix by microfacet fresnel reflectance
  vec3 brdf = (1.0 - F) * brdf_diffuse + vec3(brdf_microfacet_spec);
  return brdf;
}


// Cf. https://github.com/KhronosGroup/glTF/blob/master/specification/2.0/README.md#appendix-b-brdf-implementation
vec3 Brdf_gltfMetallicRoughness(
    vec3 wo, vec3 wi, vec3 wh, vec3 n,
    vec3 color, float metalness, float roughness) {

  float a = pow2(roughness);
  float a2 = pow2(a);
  float n_o_wh  = dot(n, wh);
  float n_o_wo  = dot(n, wo);
  float n_o_wi  = dot(n, wi);
  float wh_o_wo = dot(wh, wo);
  float wh_o_wi = dot(wh, wi);

  // Microfacet model GGX and Height-correlated G2
  float D = Brdf_GGX_D(n_o_wh, a2);
  float Vis = Brdf_GGX_Vis(n_o_wo, n_o_wi, wh_o_wo, wh_o_wi, a2);

  // Metalness blending for albedo and reflectance
  vec3 albedo = mix(color, vec3(0.0), metalness);
  vec3 F0 = mix(vec3(0.04), color, metalness);

  // Fresnel equation approx by Schlick
  vec3 F = Brdf_F_Schlick(wh_o_wo, F0);

  // Lambertian diffuse brdf
  vec3 brdf_diffuse = albedo / M_PI;

  // Microfacet specular brdf
  vec3 brdf_microfacet_specular = F * Vis * D;

  // Brdf layering by reflectance
  vec3 brdf = (1.0 - F) * brdf_diffuse + brdf_microfacet_specular;
  return brdf;
}
