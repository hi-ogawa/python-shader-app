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
```
