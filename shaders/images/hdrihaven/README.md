Download hdr file from https://hdrihaven.com and convert it to png.

```
# e.g. https://hdrihaven.com/hdri/?h=sunflowers
wget -P . https://hdrihaven.com/files/hdris/sunflowers_1k.hdr
oiiotool -i sunflowers_1k.hdr --powc 0.45 -o sunflowers_1k.hdr.png
```

Generate cube map

```
INFILE=shaders/images/hdrihaven/aft_lounge_2k.hdr \
OUT=shaders/images/hdrihaven/aft_lounge_2k.hdr \
    python -m src.app --width 1 --height 1 shaders/ex64_latlng_to_cube.glsl --offscreen /dev/zero
```
