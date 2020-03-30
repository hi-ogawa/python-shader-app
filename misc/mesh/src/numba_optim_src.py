import numpy as np


implementations = [
  ('compute_vertex_normals', 'f4[:, :](f4[:, :], u4[:, :])'),
  ('compute_smooth_vertex_normals', 'f4[:, :](f4[:, :], u4[:, :])')
]


def compute_vertex_normals(p_vs, faces):
  # @params
  #   p_vs:  Np[N, 3]
  #   faces: Np[K, L]  # this supports quad faces
  # @returns
  #   n_vs:  Np[N, 3]
  n_vs = np.zeros_like(p_vs)
  K, L = faces.shape
  for i in range(K):
    # Make normal based on 3 verts even if there's more
    p0 = p_vs[faces[i][0]]
    p1 = p_vs[faces[i][1]]
    p2 = p_vs[faces[i][2]]
    n = np.cross(p1 - p0, p2 - p0)
    n /= np.sqrt(np.sum(n**2))
    # Overwrite vertex normal by face normal (so, if there's multiple faces, one overwrites others.)
    for j in range(L):
      n_vs[faces[i][j]] = n
  return n_vs


def compute_smooth_vertex_normals(p_vs, faces):
  # @params
  #   p_vs:  Np[N, 3]
  #   faces: Np[K, L]  # this supports quad faces
  # @returns
  #   n_vs:  Np[N, 3]
  n_vs = np.zeros_like(p_vs)
  K, L = faces.shape
  for i in range(K):
    # Make normal based on 3 verts even if there's more
    p0 = p_vs[faces[i][0]]
    p1 = p_vs[faces[i][1]]
    p2 = p_vs[faces[i][2]]
    n = np.cross(p1 - p0, p2 - p0)
    n /= np.sqrt(np.sum(n**2))
    # Add up face normal to all vertices (this makes "not normalized" normal)
    for j in range(L):
      n_vs[faces[i][j]] += n
  return n_vs
