import numpy as np;  Np = np.array; Npf = lambda x: Np(x, dtype=np.float32)
from . import data, utils


def icosphere(n=3, smooth=True):
  p_vs, faces = data.hedron20()
  for _ in range(n):
    p_vs, faces = utils.geodesic_subdiv(p_vs, faces)
  verts, faces = utils.finalize(p_vs, faces, smooth)
  return verts, faces
