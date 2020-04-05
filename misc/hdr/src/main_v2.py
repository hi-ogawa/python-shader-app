import re
import numpy as np
from .numba_optim import rgbe_to_rgb, parse_rle


def parse_body(w, h, data): # int, int, uint8[:] -> float32[h, w, 3]
  data_ptr = 0
  rgb = np.zeros((h, w, 3), np.float32)
  rgbe_tmp = np.empty((w, 4), np.uint8)
  for y in range(h):
    data_ptr = parse_rle(w, data_ptr, data, rgbe_tmp)
    rgbe_to_rgb(rgbe_tmp, rgb[y])
  return rgb


def parse_header(io): # -> (width, height)
  ls = []
  while True:
    l = io.readline().decode()
    assert l != '', 'Unexpected EOI'
    l = l[:-1] # strip '\n'

    if l == 'FORMAT=32-bit_rle_rgbe':
      l2 = io.readline().decode()
      assert l2 == '\n', f"Expected '\\n' but got '{l2}'"

      l3 = io.readline().decode()
      m = re.match('\-Y (\d+) \+X (\d+)\n', l3)
      assert m, f"Expected '-Y <num> +X <num>' but got '{l3}'"

      h, w = list(map(int, m.groups()))
      return w, h


def load(io): # -> float32[h, w, 3]
  w, h = parse_header(io)
  data = np.frombuffer(io.read(), np.uint8)
  rgb = parse_body(w, h, data)
  return rgb


def load_file(filename): # -> float32[h, w, 3]
  with open(filename, 'rb') as f:
    return load(f)
