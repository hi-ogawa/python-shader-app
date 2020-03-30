# Supported feature
# - triangles only
# - v, f

import re
import numpy as np; Np = np.array


v_pattern  = (
    r'v (.*) (.*) (.*)',
    [('x', np.float32), ('y', np.float32), ('z', np.float32)])

vn_pattern = (
    r'vn (.*) (.*) (.*)',
    [('x', np.float32), ('y', np.float32), ('z', np.float32)])


def check_index_format(filename):
  with open(filename) as f:
    lines = f.read().splitlines()

  face_example = next(filter(lambda s: s.startswith('f '), lines))
  m = re.match('f (.*) (.*) (.*)', face_example)
  assert m, '[loader_obj.py] face not found'

  num_components = len(m.group(1).split('/'))
  assert num_components in [1, 2, 3]

  with_normal = False
  if num_components == 1:
    f_pattern = (
      r'f (.*) (.*) (.*)',
      [('v0', np.uint32),
       ('v1', np.uint32),
       ('v2', np.uint32)])

  if num_components == 2:
    f_pattern = (
      r'f (.*)/.* (.*)/.* (.*)/.*',
      [('v0', np.uint32),
       ('v1', np.uint32),
       ('v2', np.uint32)])

  if num_components == 3:
    with_normal = True
    f_pattern = (
      r'f (.*)/.*/(.*) (.*)/.*/(.*) (.*)/.*/(.*)',
      [('v0', np.uint32), ('vn0', np.uint32),
       ('v1', np.uint32), ('vn1', np.uint32),
       ('v2', np.uint32), ('vn2', np.uint32)])

  return with_normal, f_pattern


def load(filename): # -> (p_vs, faces)
  # Check face index format
  with_normal, f_pattern = check_index_format(filename)

  # Actually parse file via numpy.fromregex
  obj_v  = np.fromregex(filename, *v_pattern)
  obj_f  = np.fromregex(filename, *f_pattern)

  p_vs   = np.stack([obj_v['x'],  obj_v['y'],  obj_v['z']] ).T
  faces  = np.stack([obj_f['v0'], obj_f['v1'], obj_f['v2']]).T - 1
  return p_vs, faces
