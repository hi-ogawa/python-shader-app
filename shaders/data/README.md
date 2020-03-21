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
