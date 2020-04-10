import unittest, os
import numpy as np
from . import data, utils, loader_ply, loader_obj, loader_gltf


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

  def test_misc01(self):
    p_vs, faces = data.hedron12()
    faces = utils.pantas_to_tris(faces)
    self.assertEqual(p_vs.shape, (20, 3))
    self.assertEqual(faces.shape, (12 * 3, 3))

  def test_misc02(self):
    p_vs, faces = data.hedron4()
    p_vs, faces = utils.geodesic_subdiv(p_vs, faces)
    self.assertEqual(p_vs.shape, (4 + 6, 3))
    self.assertEqual(faces.shape, (4 * 4, 3))

  def test_misc03(self):
    p_vs, faces = data.grid(2, 3)
    self.assertEqual(p_vs.shape, ((2 + 1) * (3 + 1), 2))
    self.assertEqual(faces.shape, (2 * 3, 4))
    expected1 = np.float32([
        [[0, 0], [1, 0], [2, 0]],
        [[0, 1], [1, 1], [2, 1]],
        [[0, 2], [1, 2], [2, 2]],
        [[0, 3], [1, 3], [2, 3]]]).reshape((-1, 2))
    expected2 = np.uint32([
        [0, 1,  4,  3],
        [1, 2,  5,  4],
        [3, 4,  7,  6],
        [4, 5,  8,  7],
        [6, 7, 10,  9],
        [7, 8, 11, 10]])
    self.assertTrue(np.allclose(p_vs * [2, 3], expected1))
    self.assertTrue(np.all(faces == expected2))

  def test_misc04(self):
    p_vs, faces = data.grid_torus(2, 3)
    self.assertEqual(p_vs.shape, (2 * 3, 2))
    self.assertEqual(faces.shape, (2 * 3, 4))
    expected1 = np.float32([
        [[0, 0], [1, 0]],
        [[0, 1], [1, 1]],
        [[0, 2], [1, 2]]]).reshape((-1, 2))
    expected2 = np.uint32([
        [0, 1, 3, 2],
        [1, 0, 2, 3],
        [2, 3, 5, 4],
        [3, 2, 4, 5],
        [4, 5, 1, 0],
        [5, 4, 0, 1]])
    self.assertTrue(np.allclose(p_vs * [2, 3], expected1))
    self.assertTrue(np.all(faces == expected2))

  def test_misc05(self):
    p_vs, faces = data.torus()
    verts, faces = utils.finalize(p_vs, faces, smooth=True)
    self.assertEqual(faces.shape, (8192, 3))

  def test_misc06(self):
    ps = data.circle(n=7)             # float[?, 2]
    ps = np.pad(ps, ((0,0), (0, 1)))  # float[?, 3]
    p_vs, faces = utils.extrude_line(ps, m=11)
    self.assertEqual(p_vs.shape, (7 * 11, 3))
    self.assertEqual(faces.shape, (7 * 11, 4))

  def test_misc07(self):
    ps = data.torus_knot(3, 2, n=11, r0=2, r1=1)  # float[?, 3]
    normal_hints = utils.normalize(ps)
    p_vs, faces = utils.extrude_line_with_normal_hint(ps, normal_hints, m=13, r=0.5)
    self.assertEqual(p_vs.shape, (11 * 13, 3))
    self.assertEqual(faces.shape, (11 * 13, 4))

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


  def test_loader_obj(self):
    relpath = '../../bvh/data/spider.obj'
    filename = os.path.join(os.path.dirname(__file__), relpath)
    p_vs, faces = loader_obj.load(filename)
    self.assertEqual(p_vs.shape, (762, 3))
    self.assertEqual(faces.shape, (1368, 3))


  def test_loader_gltf(self):
    relpath1 = '../../bvh/data/gltf/DamagedHelmet/DamagedHelmet.gltf'
    relpath2 = '../../bvh/data/gltf/DamagedHelmet/DamagedHelmet.bin'
    gltf_file = os.path.join(os.path.dirname(__file__), relpath1)
    buffer_file = os.path.join(os.path.dirname(__file__), relpath2)
    verts_dict, faces = loader_gltf.load(gltf_file, buffer_file)
    self.assertEqual(set(verts_dict.keys()), {'POSITION', 'NORMAL', 'TEXCOORD_0'})
    p_vs, n_vs, uv_vs = verts_dict['POSITION'], verts_dict['NORMAL'], verts_dict['TEXCOORD_0']
    self.assertEqual(p_vs.shape, (14556, 3))
    self.assertEqual(n_vs.shape, (14556, 3))
    self.assertEqual(uv_vs.shape, (14556, 2))
    self.assertEqual(faces.shape, (46356 // 3, 3))
