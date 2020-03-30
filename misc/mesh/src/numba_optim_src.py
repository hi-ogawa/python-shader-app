import numpy as np


implementations = [
  ('compute_smooth_vertex_normals', 'f4[:, :](f4[:, :], u4[:, :])')
]


def compute_smooth_vertex_normals(p_vs, faces):
  # @params
  #   p_vs:  Np[N, 3]
  #   faces: Np[K, 3]
  # @returns
  #   n_vs:  Np[N, 3]
  n_vs = np.zeros_like(p_vs)
  for i in range(len(faces)):
    p0 = p_vs[faces[i][0]]
    p1 = p_vs[faces[i][1]]
    p2 = p_vs[faces[i][2]]
    n = np.cross(p1 - p0, p2 - p0)
    n /= np.sqrt(np.sum(n**2))
    n_vs[faces[i][0]] += n
    n_vs[faces[i][1]] += n
    n_vs[faces[i][2]] += n
  return n_vs
