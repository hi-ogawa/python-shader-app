Download all hdr files from http://www.pauldebevec.com/Probes/

```
curl -H 'user-agent:' http://www.pauldebevec.com/Probes/  \
| python -c 'import sys, re; print(*set(re.findall(r"HREF=\"(.*\.hdr)\"", sys.stdin.read())))'  \
| xargs -d ' ' -I@  wget -P . http://www.pauldebevec.com/Probes/@
```

Convert all hdr to png

```
for FILE in *.hdr; do
  oiiotool -i "${FILE}" --powc 0.45 -o "${FILE}.png"
done
```

Convert cross map to cube map

```
for FILE in shaders/images/pauldebevec/*_cross.hdr; do
python - <<___
from shaders.images.pauldebevec.cross_to_cube import *
convert("$FILE")
___
done
```


Convert cube map to latlng map

```
for FILE in shaders/images/pauldebevec/*_cross.hdr; do
  H=512 INFILE="${FILE}" \
    python -m src.app --width 1 --height 1 shaders/ex65_cube_to_latlng.glsl --offscreen /dev/zero
done
```
