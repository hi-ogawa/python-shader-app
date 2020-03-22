Misc data used from shaders


- Generating ssbo_test00.bin (Red-Green color gradient)

```python
import numpy as np

t = np.linspace(0, 1, num=2**8, dtype=np.float32)
r, g = np.meshgrid(t, t)
b = np.zeros_like(r)
a = np.ones_like(r)
data = np.stack([r, g, b, a], axis=2)

with open('shaders/data/ssbo_test00.bin', 'wb') as f:
  f.write(data)
```


- Build Bvh (cf. misc/bvh)

```
cd misc/bvh
ninja -C build/Release ex04
./build/Release/ex04 --infile data/bunny/reconstruction/bun_zipper.ply --outfile ../../shaders/data/bunny
./build/Release/ex04 --infile data/dragon_recon/dragon_vrip_res2.ply --outfile ../../shaders/data/dragon2
./build/Release/ex04 --infile data/octahedron.ply --outfile ../../shaders/data/octahedron
```
