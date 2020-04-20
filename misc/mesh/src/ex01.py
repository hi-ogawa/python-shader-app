import numpy as np;  Np = np.array; Npf = lambda x: Np(x, dtype=np.float32)
from .utils import soa_to_aos


def make_axes(i, bound):
  p = Npf([0, 0, 0])
  p[i] = 1
  p_vs = bound * Npf([ +p, -p ])
  c_vs = Npf([[*p, 0.8], [*p, 0.8]])
  return soa_to_aos(p_vs, c_vs)


def make_grid(i, bound):
  p_vs = []
  c_vs = []
  jj = (i + 1) % 3
  kk = (i + 2) % 3
  for j, k in [[jj, kk], [kk, jj]]:
    for l in range(- bound, bound + 1):
      if l == 0:
        continue
      p1 = Npf([0, 0, 0])
      p2 = Npf([0, 0, 0])
      p1[j] = p2[j] = l
      p1[k] = + bound
      p2[k] = - bound
      p_vs += [p1, p2]
      c_vs += [Npf([1, 1, 1, 0.3]), Npf([1, 1, 1, 0.3])]
  return soa_to_aos(Npf(p_vs), Npf(c_vs))


def make_coordinate_grids(axes=[0, 2], grids=[1], bound=10):
  verts = np.empty((0, 7), np.float32)
  for i in axes:
    axis_verts = make_axes(i, bound)
    verts = np.concatenate([axis_verts, verts], axis=0)
  for i in grids:
    grid_verts = make_grid(i, bound)
    verts = np.concatenate([grid_verts, verts], axis=0)

  indices = np.arange(2 * len(verts), dtype=np.uint32)
  return bytes(verts), bytes(indices)
