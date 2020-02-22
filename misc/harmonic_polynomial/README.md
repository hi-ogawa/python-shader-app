- Derive spherical harmonics via ladder operator
- Generate macros for ex38_spherical_harmonics.glsl

```
python -c 'import main; print(main.generate_legendre_macro(3))'
#define SH_LEGENDRE(_) \
  _((1.0/8.0)*sqrt(35)*(SH_SIN_THETA*(SH_SIN_THETA*SH_SIN_THETA))/sqrt(SH_PI)) \
  _(-1.0/8.0*sqrt(210)*SH_COS_THETA*SH_SIN_THETA*SH_SIN_THETA/sqrt(SH_PI)) \
  _((1.0/8.0)*(4*sqrt(21)*SH_SIN_THETA*(SH_COS_THETA*SH_COS_THETA) - sqrt(21)*SH_SIN_THETA*(SH_SIN_THETA*SH_SIN_THETA))/sqrt(SH_PI)) \
  _(-1.0/4.0*(-3*sqrt(7)*SH_COS_THETA*SH_SIN_THETA*SH_SIN_THETA + 2*sqrt(7)*(SH_COS_THETA*(SH_COS_THETA*SH_COS_THETA)))/sqrt(SH_PI)) \
  _(-1.0/8.0*(4*sqrt(21)*SH_SIN_THETA*(SH_COS_THETA*SH_COS_THETA) - sqrt(21)*SH_SIN_THETA*(SH_SIN_THETA*SH_SIN_THETA))/sqrt(SH_PI)) \
  _(-1.0/8.0*sqrt(210)*SH_COS_THETA*SH_SIN_THETA*SH_SIN_THETA/sqrt(SH_PI)) \
  _(-1.0/8.0*sqrt(35)*SH_SIN_THETA*(SH_SIN_THETA*SH_SIN_THETA)/sqrt(SH_PI))
```
