Objectives

- Explore font data structure, rendering, etc...
- Explore how to wrap c api with python ctypes
- Create simple font (cf. make_font_macro.py, ex36_font_v2.glsl)


References

- https://github.com/nothings/stb/blob/master/stb_truetype.h
- https://www.freetype.org/freetype2/docs/tutorial/step2.html
- https://developer.apple.com/fonts/TrueType-Reference-Manual/
- https://docs.python.org/3/library/ctypes.html
- https://github.com/rougier/freetype-py/blob/master/examples/glyph-metrics.py
- https://www.shadertoy.com/view/XdtSD4


Usage

```
# Download stb_truetype.h
curl -L 'https://github.com/nothings/stb/blob/f54acd4e13430c5122cab4ca657705c84aa61b08/stb_truetype.h?raw=true' \
  > thirdparty/stb/stb_truetype.h

# Build
CC=clang CXX=clang++ LDFLAGS=-fuse-ld=lld \
  cmake -B build -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Debug
ninja -C build

# Run examples

# - Basic infomation of glyph
./build/ex00_font_info /usr/share/fonts/TTF/Roboto-Regular.ttf J 16

# - Same as above but use python's ctypes to access stbtt api
python src/ex00_font_info.py

# - Same as above but with convinient wrapper stbtt.py
python -c 'from src.ex01_stbtt import main; main("/usr/share/fonts/TTF/Roboto-Regular.ttf", "J")'

# - Draw glyph shape and metrics via matplotlib
pip install -r requirements.txt
python -c 'from src.ex02_metrics_and_shape import main; \
    main("/usr/share/fonts/TTF/Roboto-Regular.ttf", "J", "images/ex02__Roboto-Regular__J.png", [600, 500], legend=True)'
python -c 'from src.ex02_metrics_and_shape import main; \
    main("/usr/share/fonts/TTF/Roboto-Regular.ttf", "Привет", "images/ex02__Roboto-Regular__Привет.png", [800, 400])'

# - Draw all ascii characters
python -c '\
  from src.ex02_metrics_and_shape import main; \
  file = "/usr/share/fonts/OpenImageIO/DroidSansMono.ttf"; \
  outfile = "images/ex02__DroidSansMono__{c}.png"; \
  [main(file, chr(i), outfile.format(c=i), [400, 400]) for i in range(ord(" "), ord("~") + 1)]'
```
