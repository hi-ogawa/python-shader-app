import numpy as np;  Np = np.array
from .numba_optim import \
    compute_vertex_normals, compute_smooth_vertex_normals
from . import subdivision


# structure-of-array to array-of-structure
def soa_to_aos(*soa):
  # Np[N, M1], Np[N, M2], ... ->  Np[N, M1 + M2 + ...]
  return np.concatenate(soa, axis=1)


def quads_to_tris(faces):
  # Np[N, 4] -> Np[2 * N, 3]
  return faces[..., [0, 1, 2, 0, 2, 3]].reshape((-1, 3))

def pantas_to_tris(faces):
  # Np[N, 5] -> Np[3 * N, 3]
  return faces[..., [0, 1, 2,  0, 2, 3,  0, 3, 4]].reshape((-1, 3))

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


def subdiv(p_vs, faces, n):
  for i in range(n):
    p_vs, faces = subdivision.subdivision(p_vs, faces)
  p_vs = Np(p_vs, dtype=np.float32)
  faces = Np(faces, dtype=np.uint32)
  if n > 0:
    faces = quads_to_tris(faces)
  return p_vs, faces


def min_max(i, j):
  return min(i, j), max(i, j)


# Cf. Mostly copied from subdivision.py
def process_neighbor20(neighbor20, nV): # -> (neighbor201, neighbor10, vertex_deg)
  neighbor001 = [[] for _ in range(nV)]  # "directed (v0 < v1)" adjacency list
  neighbor10  = []
  vertex_deg  = [0 for _ in range(nV)]
  nE = 0

  # 1st pass: enumerate unique edges by filtering face-ccw vertex pair
  for vs in neighbor20:
    for v0, v1 in zip(vs, np.roll(vs, -1, axis=0)):
      vertex_deg[v0] += 1

      # NOTE: if there's a boundary edge with v0 > v1, then it will not be counted.
      if v0 < v1:
        neighbor001[v0].append([v1, nE])  # current nE as "edge id"
        neighbor10.append([v0, v1])
        nE += 1

  # 2nd pass: extend neighbor20 to include edge id
  nF = len(neighbor20)
  neighbor201 = [[] for _ in range(nF)]
  for f, vs in enumerate(neighbor20):
    for v0, v1 in zip(vs, np.roll(vs, -1, axis=0)):
      v_m, v_M = min_max(v0, v1)
      _, e = next(filter(lambda v_e: v_e[0] == v_M, neighbor001[v_m]))
      neighbor201[f].append([v0, e])

  return neighbor201, neighbor10, vertex_deg


def geodesic_subdiv(p_vs, faces):
  assert faces.shape[1] == 3

  V = len(p_vs)
  neighbor201, neighbor10, _ = process_neighbor20(faces, V)
  neighbor10 = Np(neighbor10, np.uint32)

  E = len(neighbor10)
  F = len(neighbor201)

  new_p_vs = np.empty_like(p_vs, shape=(V + E, 3))
  new_faces = np.empty_like(faces, shape=(4 * F, 3))

  # new verts + middle of old verts (projeced to unit sphere)
  new_p_vs[:V] = p_vs
  new_p_vs[V:] = (p_vs[neighbor10[:, 0]] + p_vs[neighbor10[:, 1]]) / 2
  new_p_vs /= np.sqrt(np.sum(new_p_vs**2, axis=1, keepdims=True))

  # new faces
  for f, ((v0, e0), (v1, e1), (v2, e2)) in enumerate(neighbor201):
    new_faces[4 * f + 0] = [V + e0, V + e1, V + e2]
    new_faces[4 * f + 1] = [V + e0,     v1, V + e1]
    new_faces[4 * f + 2] = [V + e1,     v2, V + e2]
    new_faces[4 * f + 3] = [V + e2,     v0, V + e0]

  return new_p_vs, new_faces
