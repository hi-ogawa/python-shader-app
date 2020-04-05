import unittest, os, timeit, tempfile
import numpy as np
from . import main, main_v2, irradiance


def make_gradient(w, h): # -> float32[h, w, 3]
  r = np.linspace(0, 1, num=w, dtype=np.float32)
  g = np.linspace(0, 1, num=h,  dtype=np.float32)
  r, g = np.meshgrid(r, g)
  rgb = np.stack([r, g, np.zeros_like(r)], axis=-1)  # float32[h, w, 3]
  return rgb


def join_relative(this, that):
  return os.path.join(os.path.dirname(this), that)


class TestMisc(unittest.TestCase):
  def test_misc00(self):
    filename = join_relative(__file__, '../../../shaders/images/hdrihaven/sunflowers_1k.hdr')
    with open(filename, 'rb') as f:
      rgb = main.load(f)
    with open(filename, 'rb') as f:
      rgb_v2 = main_v2.load(f)
    self.assertTrue(np.all(rgb == rgb_v2))
    self.assertEqual(rgb.dtype, np.float32)
    self.assertEqual(rgb.shape, (2**9, 2**10, 3))

  def test_bench00(self):
    filename = join_relative(__file__, '../../../shaders/images/hdrihaven/sunflowers_4k.hdr')
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

  def test_misc03(self):
    # Test irradiance (Li = 1  ==>  Irrad = pi)
    w_in, h_in = 256, 128
    g = np.ones((h_in, w_in), dtype=np.float32)
    w_out, h_out = 64, 32
    result = irradiance.make_irradiance_map_single(g, w_out, h_out)
    self.assertTrue(np.max(np.abs(result - np.pi) < 0.001))

  def test_misc04(self):
    filename = join_relative(__file__, '../../../shaders/images/hdrihaven/fireplace_1k.hdr')
    with open(filename, 'rb') as f:
      rgb = main.load(f)
    w_out, h_out = 256, 128
    rgb_irr = irradiance.make_irradiance_map(rgb, w_out, h_out)

  def test_misc05(self):
    filename = join_relative(__file__, '../../../shaders/images/hdrihaven/fireplace_1k.hdr')
    with open(filename, 'rb') as f:
      rgb = main.load(f)
    w_out, h_out = 256, 128
    rgb_irr = irradiance.make_irradiance_map(rgb, w_out, h_out)
