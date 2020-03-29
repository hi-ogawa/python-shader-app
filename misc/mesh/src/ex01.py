import numpy as np;  Np = np.array; Npf = lambda x: Np(x, dtype=np.float32)
from .utils import soa_to_aos


def make_axes(bound):
  p_vs = Npf(np.empty((6, 3)))
  c_vs = Npf(np.empty((6, 4)))
  for i in range(3):
    p = Npf([0, 0, 0])
    p[i] = 1
    p_vs[2 * i + 0] = + bound * p
    p_vs[2 * i + 1] = - bound * p
    c_vs[2 * i + 0] = Npf([*p, 0.9])
    c_vs[2 * i + 1] = Npf([*p, 0.9])
  return soa_to_aos(p_vs, c_vs)


def make_grid(i, bound):
  p_vs = []
  c_vs = []
  jj = (i + 1) % 3
  kk = (i + 2) % 3
  for j, k in [[jj, kk], [kk, jj]]:
    for l in range(- bound, bound + 1):
      p1 = Npf([0, 0, 0])
      p2 = Npf([0, 0, 0])
      p1[j] = p2[j] = l
      p1[k] = + bound
      p2[k] = - bound
      p_vs += [p1, p2]
      c_vs += [Npf([1, 1, 1, 0.5]), Npf([1, 1, 1, 0.5])]
  return soa_to_aos(Npf(p_vs), Npf(c_vs))


def make_coordinate_grids(bound=int(1e1)):
  axes_verts = make_axes(bound)
  grid_verts = make_grid(1, bound)
  verts = np.concatenate([axes_verts, grid_verts], axis=0)
  indices = np.arange(2 * len(verts), dtype=np.uint32)
  return bytes(verts), bytes(indices)
