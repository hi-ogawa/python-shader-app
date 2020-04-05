import re
import numpy as np


def rgbe_to_rgb(rgbe): # uint8[.., 4] -> float32[.., 3]
  rgb = rgbe[..., :3].astype(np.float32)
  e = rgbe[..., 3:].astype(np.int32)
  return rgb * (2.0 ** (e - (128 + 8)))


def rgb_to_rgbe(rgb): # float32[.., 3] -> uint8[.., 4]
  assert rgb.shape[-1] == 3
  rgbe = np.empty((*rgb.shape[:-1], 4), dtype=np.uint8)  # uint8[.., 4]
  rgb_max = np.max(rgb, axis=-1, keepdims=True)  # float32[.., 1]
  mm, ee = np.frexp(rgb_max)
  rgbe[..., 3]  = (ee[..., 0] + 128).astype(np.uint8)
  rgbe[..., :3] = (rgb / 2.0**(ee - 8)).astype(np.uint8)
  return rgbe


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


def parse_rle(w, io): # -> uint8[w, 4]
  h = io.read(4)
  assert len(h) == 4
  assert h[0] == 2 and h[1] == 2

  scan_width = (h[2] << 8) + h[3]
  assert scan_width == w

  buffer = np.zeros((w, 4), np.uint8)

  # process 4 components
  for c in range(4):
    i = 0
    while i < w:
      b = io.read(1)[0]
      if b > 128:
        count = b - 128
        run = io.read(1)[0]
        buffer[i:i+count, c] = run
      else:
        count = b
        non_run = io.read(count)
        buffer[i:i+count, c] = np.frombuffer(non_run, np.uint8)
      i += count

  return buffer


def parse_scanline(w, io): # -> float32[w, 3]
  rgbe = parse_rle(w, io)
  rgb = rgbe_to_rgb(rgbe)
  return rgb


def parse_body(w, h, io): # -> float32[h, w, 3]
  rgb = np.zeros((h, w, 3), np.float32)
  for y in range(h):
    rgb[y] = parse_scanline(w, io)
  return rgb


def load(io): # -> float32[h, w, 3]
  w, h = parse_header(io)
  rgb = parse_body(w, h, io)
  assert io.read() == b''
  return rgb


def write_header(io, w, h):
  header = f"""\
FORMAT=32-bit_rle_rgbe

-Y {h} +X {w}
"""

  io.write(bytes(header, 'ascii'))


def write_rle(io, w, data): # uint8[w, 4] -> bytes
  # scanline header
  io.write(bytes([2, 2, w >> 8, w & 0xff]))

  # TODO: currently no run-length-encoding
  count = min(128, w)

  # process 4 components (without rle)
  for c in range(4):
    i = 0
    while i < w:
      io.write(bytes([count]))
      io.write(bytes(data[i:i+count, c]))
      i += count


def write(io, data): # float32[h, w, 3]
  h, w = data.shape[:2]
  write_header(io, w, h)
  data_rgbe = rgb_to_rgbe(data)  # uint8[h, w, 4]
  for y in range(h):
    write_rle(io, w, data_rgbe[y])
