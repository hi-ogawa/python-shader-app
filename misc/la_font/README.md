LA Font (Line/Arc Font)


Demo (on shadertoy)

- https://www.shadertoy.com/view/3tySRR


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
python -m src.app --width 300 --height 600 shaders/ex36_font_v2.glsl

# Test arc format convertion
python -c 'from convert_arc import *; test("font.svg")'
```


TODO

- [x] Auto convert arc representation (svg <-> our format)
- [ ] Generate truetype font file
- [ ] Improve some bad looking ones ("s", "4", "5", etc..)
- [ ] More codepoints
