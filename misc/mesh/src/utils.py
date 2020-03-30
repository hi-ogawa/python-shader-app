import numpy as np;  Np = np.array
from .numba_optim import \
    compute_vertex_normals, compute_smooth_vertex_normals


# structure-of-array to array-of-structure
def soa_to_aos(*soa):
  # Np[N, M1], Np[N, M2], ... ->  Np[N, M1 + M2 + ...]
  return np.concatenate(soa, axis=1)


def quads_to_tris(faces):
  # Np[N, 4] -> Np[2 * N, 3]
  return faces[..., [0, 1, 2, 0, 2, 3]].reshape((-1, 3))


def uniqify_vertices(verts, faces):
  # @params
  #   verts: Np[N, M]
  #   faces: Np[K, L]
  # @returns
  #   verts: Np[K*L, M]
  #   faces: Np[K, L]
  K, L = faces.shape
  new_faces = np.arange(K * L, dtype=np.uint32).reshape((K, L))
  new_verts = verts[faces.reshape(-1)]
  return new_verts, new_faces


def compute_face_normals(p_vs, faces):
  # @params
  #   p_vs:  Np[N, 3]
  #   faces: Np[K, 3]
  # @returns
  #   n_vs:  Np[K, 3]
  n_vs = np.empty((len(faces), 3), dtype=p_vs.dtype)
  for f, vs in enumerate(faces):
    ps = [p_vs[v] for v in vs]
    n = np.cross(ps[1] - ps[0], ps[2] - ps[0])
    n_vs[f] = n / np.linalg.norm(n)
  return n_vs


def finalize(p_vs, faces, smooth):
  assert p_vs.dtype == np.float32
  assert faces.dtype == np.uint32
  if smooth:
    n_vs = compute_smooth_vertex_normals(p_vs, faces)
  else:
    p_vs, faces = uniqify_vertices(p_vs, faces)
    n_vs = compute_vertex_normals(p_vs, faces)
  verts = soa_to_aos(p_vs, n_vs)
  return verts, faces


# scale/translate into [-1, 1]^3
def normalize_positions(p_vs):
  m = np.min(p_vs, axis=0)
  M = np.max(p_vs, axis=0)
  c = (m + M) / 2
  s = (M - m)[np.argmax(M - m)]
  return (p_vs - c) / s * 2
