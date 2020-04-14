import unittest, os
import numpy as np
from . import utils, table_all_faces, table_marching_cube


class TestMisc(unittest.TestCase):
  def test_misc00(self):
    f = [0.0, 0.0, 0.8, 1.0, 0.0, 0.0, 0.0, 0.8]
    threshold = 0.5
    positions, faces = utils.marching_cube_single(f, threshold, table_all_faces.data)
    self.assertEqual(positions.shape, (8, 3))
    self.assertEqual(faces.shape, (12, 3))


  def test_misc01(self):
    stats, vert_data, face_data = utils.make_data(table_all_faces.data)
    self.assertEqual(np.max(stats[:, 0]), 16)
    self.assertEqual(np.max(stats[:, 1]), 28)
    self.assertEqual(len(vert_data), 2560)
    self.assertEqual(len(face_data), 4100)

    stats, vert_data, face_data = utils.make_data(table_marching_cube.data)
    self.assertEqual(np.max(stats[:, 0]), 12)
    self.assertEqual(np.max(stats[:, 1]), 6)
    self.assertEqual(len(vert_data), 1536)
    self.assertEqual(len(face_data), 836)
