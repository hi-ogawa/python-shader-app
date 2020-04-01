import unittest, os, timeit
import numpy as np
from . import main, main_v2

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
