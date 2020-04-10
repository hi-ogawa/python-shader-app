Download hdr file from https://hdrihaven.com and convert it to png.

```
# e.g. https://hdrihaven.com/hdri/?h=entrance_hall
wget -P shaders/images/hdrihaven -c https://hdrihaven.com/files/hdris/entrance_hall_2k.hdr
```

Generate spherical harmonics coefficient

```
python -c 'from misc.hdr.src.irradiance import *; print_M_from_file("shaders/images/hdrihaven/entrance_hall_2k.hdr")'
```


Generate cube map

```
INFILE=shaders/images/hdrihaven/aft_lounge_2k.hdr \
OUT=shaders/images/hdrihaven/aft_lounge_2k.hdr \
    python -m src.app --width 1 --height 1 shaders/ex64_latlng_to_cube.glsl --offscreen /dev/zero
```
