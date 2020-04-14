import os, itertools
import numpy as np


kCornerPositions = np.array([
  [0, 0, 0],
  [1, 0, 0],
  [1, 1, 0],
  [0, 1, 0],
  [0, 0, 1],
  [1, 0, 1],
  [1, 1, 1],
  [0, 1, 1],
], np.float32)


def interpolate_position(v0, v1, f0, f1, threshold):
  if v0 == v1:
    return kCornerPositions[v0]

  p0 = kCornerPositions[v0]
  p1 = kCornerPositions[v1]
  p = p0 + (threshold - f0) / (f1 - f0) * (p1 - p0)
  return p


def marching_cube_single(f, threshold, table): # (float[8], float) -> float[:, 3], int[:, 3]
  key = tuple([ int(threshold < f[i]) for i in range(8) ])
  verts, faces = table[key]

  positions = np.empty((len(verts), 3), np.float32)
  for i, (v0, v1) in enumerate(verts):
    positions[i] = interpolate_position(v0, v1, f[v0], f[v1], threshold)

  faces = np.uint32(faces)
  return positions, faces


def make_data(table):
  ls_verts = [x[0] for x in table.values()]
  ls_faces = [x[1] for x in table.values()]
  ls_num_verts = np.array([len(x) for x in ls_verts])
  ls_num_faces = np.array([len(x) for x in ls_faces])
  ls_cum_num_verts = np.cumsum(ls_num_verts)
  ls_cum_num_faces = np.cumsum(ls_num_faces)
  stats = np.zeros((2**8, 4), np.int)
  stats[:, 0]  = ls_num_verts
  stats[:, 1]  = ls_num_faces
  stats[1:, 2] = ls_cum_num_verts[:-1]
  stats[1:, 3] = ls_cum_num_faces[:-1]
  vert_data = np.array(list(itertools.chain(*ls_verts)))
  face_data = np.array(list(itertools.chain(*ls_faces)))
  return stats, vert_data, face_data


def emit_c_data(table):
  stats, vert_data, face_data = make_data(table)

  # emit stats (number of verts/faces and offset into table)
  print('int MarchingCube_data1[] = {')
  print(*stats.reshape(-1), sep=', ')
  print('};')

  # emit verts
  print('int MarchingCube_data2[] = {')
  print(*vert_data.reshape(-1), sep=', ')
  print('};')

  # emit faces
  print('int MarchingCube_data3[] = {')
  print(*face_data.reshape(-1), sep=', ')
  print('};')
