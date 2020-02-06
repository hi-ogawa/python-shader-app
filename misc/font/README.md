Objectives

- Explore font data structure, rendering, etc...
- Explore how to wrap c api with python ctypes


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

# Build example
CC=clang CXX=clang++ LDFLAGS=-fuse-ld=lld \
  cmake -B build -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Debug
ninja -C build

# Run example
./build/ex00_font_info /usr/share/fonts/TTF/Roboto-Regular.ttf J 16

== Codepoint info ==
codepoint: 'J'
glyph_index: 47

== Global metric ==
ascent: 2146
descent: -555
line_gap: 0
x_min: -1825
y_min: -555
x_max: 4188
y_max: 2163

== Font metric of 'J' ==
advance: 1130
bearing: 53
x_min: 53
y_min: -20
x_max: 972
y_max: 1456

== Glyph geometry of 'J' ==
num_vertices: 13
vertices:
  - type: move
    padding: 0
    data: [  779,  1456,     0,     0,     0,     0]
  - type: line
    padding: 0
    data: [  972,  1456,     0,     0,     0,     0]
  - type: line
    padding: 0
    data: [  972,   425,     0,     0,     0,     0]
  - type: curve
    padding: 0
    data: [  846,    98,   972,   216,     0,     0]
  - type: curve
    padding: 0
    data: [  512,   -20,   721,   -20,     0,     0]
  - type: curve
    padding: 0
    data: [  174,    91,   295,   -20,     0,     0]
  - type: curve
    padding: 0
    data: [   53,   402,    53,   202,     0,     0]
  - type: line
    padding: 0
    data: [  245,   402,     0,     0,     0,     0]
  - type: curve
    padding: 0
    data: [  313,   207,   245,   277,     0,     0]
  - type: curve
    padding: 0
    data: [  512,   137,   382,   137,     0,     0]
  - type: curve
    padding: 0
    data: [  704,   212,   631,   137,     0,     0]
  - type: curve
    padding: 0
    data: [  779,   422,   778,   287,     0,     0]
  - type: line
    padding: 0
    data: [  779,  1456,     0,     0,     0,     0]

== Rendering 'J' ==
    .i
    iM
    iM
    iM
    iM
    iM
..  iV
:M  M:
 o@@o
```
