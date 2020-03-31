// require: [math_v0.glsl]

float Brdf_beckmannG(float mu) {
  // Masking-shadowing function by [3/3] Pade approx.
  float g =
      (0.0 + 42.5770668488687*mu + -2.73558953267639e-13*mu*mu + 3.54808890407244*mu*mu*mu)
      / (16.9857921414919 + 21.2885334244342*mu + 9.90837874920349*mu*mu + 1.77404445203615*mu*mu*mu);
  g = min(1.0, g);
  return g;
}


vec3 Brdf_default(
    vec3 wo, vec3 wi, vec3 wh, vec3 n,
    vec3 diffuse_albedo, float beckmann_stddev) {
  //
  // Microfacet specular BRDF (m: half vector)
  //   F(m, wi) D(n, m) G(n, m, wi, wo) / 4 (n.wo) (n.wi)
  //

  // Fresnel equation reflectance (IOR = 1.5) by Schlick's approx
  float F1 = 0.04;  // at dot(wo, wh) = cos(t) = 1
  float F = F1 + (1.0 - F1) * pow5(1.0 - dot(wo, wh));

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

  // Microfacet model
  float a = pow2(roughness);
  float a2 = pow2(a);
  float D  = a2 / (M_PI * pow2(pow2(dot(n, wh)) * (a2 - 1.0) + 1.0));
  float Vis_tmp1 = dot(n, wi) * sqrt(pow2(dot(n, wo)) * (1.0 - a2) + a2);
  float Vis_tmp2 = dot(n, wo) * sqrt(pow2(dot(n, wi)) * (1.0 - a2) + a2);
  float Vis = 0.5 / (Vis_tmp1 + Vis_tmp2);

  // Metalness blending for albedo and reflectance
  vec3 albedo = mix(color, vec3(0.0), metalness);
  vec3 F0 = mix(vec3(0.04), color, metalness);

  // Fresnel equation approx by Schlick
  vec3 F = F0 + (1.0 - F0) * pow5(1.0 - dot(wo, wh));

  // Lambertian diffuse brdf
  vec3 brdf_diffuse = albedo / M_PI;

  // Microfacet specular brdf
  vec3 brdf_microfacet_specular = F * Vis * D;

  // Brdf layering by reflectance
  vec3 brdf = (1.0 - F) * brdf_diffuse + brdf_microfacet_specular;
  return brdf;
}
