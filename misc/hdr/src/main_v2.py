import re
import numpy as np
from .numba_optim import rgbe_to_rgb, parse_rle
from .main import parse_header


def parse_body(w, h, data): # int, int, uint8[:] -> float32[h, w, 3]
  data_ptr = 0
  rgb = np.zeros((h, w, 3), np.float32)
  rgbe_tmp = np.empty((w, 4), np.uint8)
  for y in range(h):
    data_ptr = parse_rle(w, data_ptr, data, rgbe_tmp)
    rgbe_to_rgb(rgbe_tmp, rgb[y])
  return rgb


def load(io): # -> float32[h, w, 3]
  w, h = parse_header(io)
  data = np.frombuffer(io.read(), np.uint8)
  rgb = parse_body(w, h, data)
  return rgb


def load_file(filename): # -> float32[h, w, 3]
  with open(filename, 'rb') as f:
    return load(f)
