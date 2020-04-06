import numpy as np
import misc.hdr.src.main as hdr

PATTERNS = [
  ['pz', [1, 1], False],
  ['nx', [1, 0], False],
  ['nz', [3, 1], True ],
  ['px', [1, 2], False],
  ['py', [0, 1], False],
  ['ny', [2, 1], False],
]

def convert(infile):
  cross = hdr.load_file(infile)  # float[4 * size, 3 * size]
  size = cross.shape[0] // 4

  for name, offset, flip in PATTERNS:
    y, x = np.array(offset) * size
    rgb = cross[y:, x:][:size, :size]
    if flip:
      rgb = np.flip(rgb, axis=(0, 1))
    hdr.write_file(f"{infile}.{name}.hdr", rgb)
