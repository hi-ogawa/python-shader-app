Download hdr file from https://hdrihaven.com and convert it to png.

```
# e.g. https://hdrihaven.com/hdri/?h=sunflowers
wget -P . https://hdrihaven.com/files/hdris/sunflowers_1k.hdr
oiiotool -i sunflowers_1k.hdr --powc 0.45 -o sunflowers_1k.hdr.png
```
