# Supported feature
# - triangles only
# - format ascii 1.0
# - format binary_big_endian 1.0

import re
import numpy as np; Np = np.array


def load_ascii(filename): # -> (p_vs, faces)
  with open(filename) as f:
    lines = f.read().splitlines()

  assert lines[0] == 'ply'
  assert lines[1] == 'format ascii 1.0'

  num_verts = None
  num_faces = None
  end_header = None
  for i, line in enumerate(lines):
    m = re.match('element vertex (.*)', line)
    if m:
      num_verts = int(m.group(1))
    m = re.match('element vertex (.*)', line)
    if m:
      num_verts = int(m.group(1))
    m = re.match('element face (.*)', line)
    if m:
      num_faces = int(m.group(1))
    if line == 'end_header':
      end_header = i

  assert not None in [num_verts, num_faces, end_header]
  assert num_verts < 2**32

  begin = end_header + 1
  vert_lines = lines[begin : begin + num_verts]
  face_lines = lines[begin + num_verts : begin + num_verts + num_faces]

  assert all(l.split()[0] == '3' for l in face_lines)

  p_vs = Np(
    [[float(_) for _ in l.split()[:3]] for l in vert_lines],
    np.float32)
  faces = Np(
    [[int(_) for _ in l.split()[1:]] for l in face_lines],
    np.uint32)

  return p_vs, faces


def load_binary_big_endian(filename): # -> (p_vs, faces)
  with open(filename, 'rb') as f:
    assert f.readline() == b'ply\n'
    assert f.readline() == b'format binary_big_endian 1.0\n'

    num_verts = None
    num_faces = None
    while True:
      l = f.readline().decode().strip()
      if l == 'end_header': break

      m = re.match('element vertex (.*)', l)
      if m: num_verts = int(m.group(1))

      m = re.match('element face (.*)', l)
      if m: num_faces = int(m.group(1))

    bs = f.read()
    f.close()

  # Assuming format as in Armadillo.ply
  #   element vertex 172974
  #   property float x
  #   property float y
  #   property float z
  #   element face 345944
  #   property uchar intensity
  #   property list uchar int vertex_indices
  assert len(bs) == num_verts * 3 * 4 + num_faces * (1 + 1 + 3 * 4)

  ply_verts = np.frombuffer(
      bs, count=num_verts * 3,
      dtype=np.dtype(np.float32).newbyteorder('B'))
  ply_faces = np.frombuffer(
      bs, offset=num_verts * 3 * 4,
      dtype=np.dtype([('xx', 'uint8', (2,)), ('indices', 'uint32', (3,))]).newbyteorder('B'))

  verts = Np(ply_verts.reshape((-1, 3)), np.float32)
  faces = Np(ply_faces['indices'], np.uint32)
  return verts, faces


def load(filename): # -> (p_vs, faces)
  with open(filename, 'rb') as f:
    line1 = f.readline().decode()
    line2 = f.readline().decode()

  assert line1 == 'ply\n'

  m = re.match('^format (.*) 1.0$', line2)
  assert m

  ply_format = m.group(1)
  assert ply_format in ['ascii', 'binary_big_endian']

  if ply_format == 'ascii':
    return load_ascii(filename)

  if ply_format == 'binary_big_endian':
    return load_binary_big_endian(filename)
