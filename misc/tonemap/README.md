```
# Verify OpenImageIO is available
python -c 'import OpenImageIO'

# Example
PYTHONPATH=/usr/lib/python3.8/site-packages \
  python -c 'import tonemap; \
    tonemap.main(
      "../../shaders/images/hdrihaven/sunflowers_1k.hdr", \
      "../../shaders/images/hdrihaven/sunflowers_1k.hdr.tonemap.png", \
      0.5, 10.0, 0.0)'

PYTHONPATH=/usr/lib/python3.8/site-packages \
  python -c 'import tonemap, math; tonemap.solve(0.9, 0.9 + (math.exp(3) - 1) / 30, debug=True)'
x: 19.50319, g: -6.37670
x: 114.80850, g: 96769.27101
x: 104.81548, g: 35583.88844
x: 94.83269, g: 13076.73058
x: 84.87455, g: 4798.50117
x: 74.97488, g: 1754.80904
x: 65.21046, g: 636.80246
x: 55.74728, g: 227.21219
x: 46.91719, g: 78.19246
x: 39.30193, g: 24.91351
x: 33.71029, g: 6.66250
x: 30.78128, g: 1.13514
x: 30.04206, g: 0.05790
x: 30.00013, g: 0.00018
x: 30.00000, g: 0.00000
```
