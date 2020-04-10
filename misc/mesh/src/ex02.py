import numpy as np
from . import data, utils


def icosphere(n=3, smooth=True):
  p_vs, faces = data.hedron20()
  for _ in range(n):
    p_vs, faces = utils.geodesic_subdiv(p_vs, faces)
  verts, faces = utils.finalize(p_vs, faces, smooth)
  return verts, faces


def torus_by_extruding_circle(r0=1, r1=0.5, n=2**8, m=2**6):
  ps = data.circle(n=n, r=r0)       # float[?, 2]
  ps = np.pad(ps, ((0,0), (0, 1)))  # float[?, 3]
  p_vs, faces = utils.extrude_line(ps, m=m, r=r1, closed=True)
  return p_vs, faces


def torus_knot_extrude(p=3, q=2, r0=2.0, r1=1, r2=0.5, n=2**8, m=2**5):
  ps = data.torus_knot(p, q, r0, r1, n)  # float[?, 3]
  p_vs, faces = utils.extrude_line_with_normal_hint(
      ps, utils.normalize(ps), m=m, r=r2, closed=True)
  return p_vs, faces
