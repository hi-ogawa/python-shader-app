import numpy as np;  Np = np.array
from . import data, utils, subdivision

def subdiv(p_vs, faces, n):
  for i in range(n):
    p_vs, faces = subdivision.subdivision(p_vs, faces)
  p_vs = Np(p_vs, dtype=np.float32)
  faces = Np(faces, dtype=np.uint32)
  return p_vs, faces


def example(name='cube', num_subdiv=0, smooth=False):
  p_vs, faces = getattr(data, name)()
  p_vs, faces = subdiv(p_vs, faces, num_subdiv)
  verts, faces = utils.finalize(p_vs, faces, smooth)
  if faces.shape[1] == 4:
    faces = utils.quads_to_tris(faces)
  return bytes(verts), bytes(faces)
