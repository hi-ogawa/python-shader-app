Download hdr file from https://hdrihaven.com and convert it to png.

```
# e.g. https://hdrihaven.com/hdri/?h=sunflowers
wget -P . https://hdrihaven.com/files/hdris/sunflowers_1k.hdr
oiiotool -i sunflowers_1k.hdr --powc 0.45 -o sunflowers_1k.hdr.png
```

Generate cube map

```
EXEC=(python -m src.app --width 512 --height 512 shaders/ex61_cube_map_generator.glsl)
INFILE=shaders/images/hdrihaven/carpentry_shop_02_2k.hdr
OUT=shaders/images/hdrihaven/carpentry_shop_02_cubemap
INFILE=${INFILE} ROTATE3_X=0.00 ROTATE3_Y=0.00 "${EXEC[@]}" --offscreen "${OUT}_pz.png"
INFILE=${INFILE} ROTATE3_X=0.00 ROTATE3_Y=0.25 "${EXEC[@]}" --offscreen "${OUT}_nx.png"
INFILE=${INFILE} ROTATE3_X=0.00 ROTATE3_Y=0.50 "${EXEC[@]}" --offscreen "${OUT}_nz.png"
INFILE=${INFILE} ROTATE3_X=0.00 ROTATE3_Y=0.75 "${EXEC[@]}" --offscreen "${OUT}_px.png"
INFILE=${INFILE} ROTATE3_X=0.25 ROTATE3_Y=0.00 "${EXEC[@]}" --offscreen "${OUT}_py.png"
INFILE=${INFILE} ROTATE3_X=0.75 ROTATE3_Y=0.00 "${EXEC[@]}" --offscreen "${OUT}_ny.png"
```
