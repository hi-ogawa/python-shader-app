LA Font (Line/Arc Font)


Usage

```
# Font glyph defined by svg path (with custom annotation for make_font_macro.py)
font.svg

# Solve tangent (used for making glyph of "2", "&", etc...)
python -c 'from solve_tangent import *; pp(circle_point(0, 3, 1, -1, 0))'
python -c 'from solve_tangent import *; pp(circle_circle(0, 3, 0.75, 0, 1, 1))'

# Generate c preprocessor macro from svg
python misc/la_font/make_font_macro.py < misc/la_font/font.svg > shaders/utils/font_data_v0.glsl

# Run sdf rendering shader
python -m src.app --width 500 --height 500 shaders/ex36_font_v2.glsl
```


TODO

- [ ] arc representation convertion (svg <-> our format)
- [ ] Improve especially bad looking ones (s, 4, 5)
