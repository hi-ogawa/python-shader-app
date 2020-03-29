import unittest, tempfile, shutil, contextlib, os
from . import data, utils


class TestUtils(unittest.TestCase):
  def test_misc00(self):
    v_positions, faces = data.cube_quads()
    self.assertEqual(v_positions.shape, (8, 3))
    self.assertEqual(faces.shape, (6, 4))

    faces = utils.quads_to_tris(faces)
    self.assertEqual(faces.shape, (12, 3))

    v_positions, faces = utils.uniqify_vertices(v_positions, faces)
    self.assertEqual(v_positions.shape, (36, 3))
    self.assertEqual(faces.shape, (12, 3))

    f_normals = utils.compute_face_normals(v_positions, faces)
    self.assertEqual(f_normals.shape, (12, 3))

    v_normals = utils.compute_vertex_normals(v_positions, faces)
    self.assertEqual(v_normals.shape, (36, 3))

    verts = utils.soa_to_aos(v_positions, v_normals)
    self.assertEqual(verts.shape, (36, 6))
