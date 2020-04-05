import unittest, os, timeit, tempfile
import numpy as np
from . import main, main_v2


def make_gradient(w, h): # -> float32[h, w, 3]
  r = np.linspace(0, 1, num=w, dtype=np.float32)
  g = np.linspace(0, 1, num=h,  dtype=np.float32)
  r, g = np.meshgrid(r, g)
  rgb = np.stack([r, g, np.zeros_like(r)], axis=-1)  # float32[h, w, 3]
  return rgb


class TestMisc(unittest.TestCase):
  def test_misc00(self):
    relpath = '../../../shaders/images/hdrihaven/sunflowers_1k.hdr'
    filename = os.path.join(os.path.dirname(__file__), relpath)
    with open(filename, 'rb') as f:
      rgb = main.load(f)
    with open(filename, 'rb') as f:
      rgb_v2 = main_v2.load(f)
    self.assertTrue(np.all(rgb == rgb_v2))
    self.assertEqual(rgb.dtype, np.float32)
    self.assertEqual(rgb.shape, (2**9, 2**10, 3))

  def test_bench00(self):
    relpath = '../../../shaders/images/hdrihaven/sunflowers_4k.hdr'
    filename = os.path.join(os.path.dirname(__file__), relpath)
    with open(filename, 'rb') as f:
      ns = {}; ns.update(globals()); ns.update(locals())
      print(timeit.timeit('main.load(f)', number=1, globals=ns))

    with open(filename, 'rb') as f:
      ns = {}; ns.update(globals()); ns.update(locals())
      print(timeit.timeit('main_v2.load(f)', number=1, globals=ns))

  def test_misc01(self):
    w, h = 512, 256
    data = make_gradient(w, h)  # float32[h, w, 3]
    data2 = main.rgbe_to_rgb(main.rgb_to_rgbe(data)) # rgb -> rgbe -> rgb
    self.assertTrue(np.max(np.abs(data2 - data) < 0.008))

  def test_misc02(self):
    w, h = 512, 256
    data = make_gradient(w, h)  # float32[h, w, 3]

    with tempfile.NamedTemporaryFile() as f:
      main.write(f, data)
      f.seek(0)
      data2 = main.load(f)
      self.assertTrue(np.max(np.abs(data2 - data) < 0.008))
