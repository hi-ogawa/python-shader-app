import numpy as np
import numba

implementations = [
  ('rgbe_to_rgb', 'void(u1[:, :], f4[:, :])'),
  ('parse_rle', 'i8(i8, i8, u1[:], u1[:, :])'),
]


def rgbe_to_rgb(rgbe, rgb_out): # uint8[.., 4], float32[.., 3]
  rgb_out += rgbe[:, :3].astype(np.float32)
  e = rgbe[:, 3:].astype(np.int32)
  rgb_out *= 2.0 ** (e - (128 + 8))


def parse_rle(w, ptr, data, rgbe_out): # int, int, uint8[:], uint8[w, 4] -> int
  ptr += 4

  for c in numba.prange(4):
    i = 0
    while i < w:
      b = data[ptr]; ptr += 1
      if b > 128:
        count = b - 128
        run = data[ptr]; ptr += 1
        rgbe_out[i:i+count, c] = run
      else:
        count = b
        non_run = data[ptr:ptr+count];  ptr += count
        rgbe_out[i:i+count, c] = non_run
      i += count

  return ptr
