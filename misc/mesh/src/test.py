import unittest, tempfile, shutil, contextlib, os
from . import data, utils, loader_ply


class TestUtils(unittest.TestCase):
  def test_misc00(self):
    p_vs, faces = data.cube()
    self.assertEqual(p_vs.shape, (8, 3))
    self.assertEqual(faces.shape, (6, 4))

    faces = utils.quads_to_tris(faces)
    self.assertEqual(faces.shape, (12, 3))

    p_vs, faces = utils.uniqify_vertices(p_vs, faces)
    self.assertEqual(p_vs.shape, (36, 3))
    self.assertEqual(faces.shape, (12, 3))

    n_faces = utils.compute_face_normals(p_vs, faces)
    self.assertEqual(n_faces.shape, (12, 3))

    n_vs = utils.compute_vertex_normals(p_vs, faces)
    self.assertEqual(n_vs.shape, (36, 3))

    verts = utils.soa_to_aos(p_vs, n_vs)
    self.assertEqual(verts.shape, (36, 6))


  def test_loader_ply(self):
    # [format ascii 1.0]
    relpath = '../../bvh/data/bunny/reconstruction/bun_zipper_res4.ply'
    filename = os.path.join(os.path.dirname(__file__), relpath)
    p_vs, faces = loader_ply.load(filename)
    self.assertEqual(p_vs.shape, (453, 3))
    self.assertEqual(faces.shape, (948, 3))

    p_vs = utils.normalize_positions(p_vs)
    self.assertEqual(p_vs.shape, (453, 3))


  def test_loader_ply_binary(self):
    # [format binary_big_endian 1.0]
    relpath = '../../bvh/data/Armadillo.ply'
    filename = os.path.join(os.path.dirname(__file__), relpath)
    p_vs, faces = loader_ply.load(filename)
    self.assertEqual(p_vs.shape, (172974, 3))
    self.assertEqual(faces.shape, (345944, 3))
