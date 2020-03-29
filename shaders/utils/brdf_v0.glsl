// require: [math_v0.glsl]

float Brdf_beckmannG(float mu) {
  // Masking-shadowing function by [3/3] Pade approx.
  float g =
      (0.0 + 42.5770668488687*mu + -2.73558953267639e-13*mu*mu + 3.54808890407244*mu*mu*mu)
      / (16.9857921414919 + 21.2885334244342*mu + 9.90837874920349*mu*mu + 1.77404445203615*mu*mu*mu);
  g = min(1.0, g);
  return g;
}


vec3 Brdf_default(vec3 wo, vec3 wi, vec3 wh, vec3 n, vec3 diffuse_albedo, float beckmann_stddev) {
  //
  // Microfacet specular BRDF (m: half vector)
  //   F(m, wi) D(n, m) G(n, m, wi, wo) / 4 (n.wo) (n.wi)
  //

  // Fresnel equation reflectance (IOR = 1.5) by Schlick's approx
  float F1 = 0.04;
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
