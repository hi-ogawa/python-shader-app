import numpy as np;  Np = np.array
from .numba_optim import \
    compute_vertex_normals, compute_smooth_vertex_normals
from . import subdivision, data


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


def verts_from_face_attrs(num_verts, faces, face_attrs):
  # @params
  #   num_verts: int
  #   faces: Np[K, L]
  #   face_attrs: Np[K, A...]
  # @returns
  #   verts: Np[num_verts, A...]
  verts = np.empty_like(face_attrs, shape=(num_verts, ) + face_attrs.shape[1:])
  for i in range(faces.shape[1]):
    verts[faces[:, i]] = face_attrs
  return verts


def merge_face_attrs(verts, faces, face_attrs):
  verts, faces = uniqify_vertices(verts, faces)
  fattr_vs = verts_from_face_attrs(len(verts), faces, face_attrs)
  verts = soa_to_aos(verts, fattr_vs)
  return verts, faces


def finalize(p_vs, faces, smooth, face_attrs=None):
  assert p_vs.dtype == np.float32
  assert faces.dtype == np.uint32
  assert faces.shape[1] in [3, 4]
  if smooth:
    n_vs = compute_smooth_vertex_normals(p_vs, faces)
  else:
    p_vs, faces = uniqify_vertices(p_vs, faces)
    n_vs = compute_vertex_normals(p_vs, faces)
  verts = soa_to_aos(p_vs, n_vs)
  if face_attrs is not None:
    verts, faces = merge_face_attrs(verts, faces, face_attrs)
  if faces.shape[1] == 4:
    faces = quads_to_tris(faces)
  return verts, faces


def concat(*ls_verts_faces):
  assert len(ls_verts_faces) > 0
  ls_verts = [x for x, y in ls_verts_faces]
  ls_faces = [y for x, y in ls_verts_faces]
  assert all(ls_verts[0].shape[1:] == x.shape[1:] for x in ls_verts[1:])
  assert all(ls_faces[0].shape[1:] == x.shape[1:] for x in ls_faces[1:])
  new_verts = np.concatenate(ls_verts, axis=0)
  offsets = np.cumsum([0] + [len(x) for x in ls_verts[:-1]])
  new_faces = np.concatenate([faces + offset for faces, offset in zip(ls_faces, offsets)], axis=0)
  return new_verts, new_faces


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


def subdiv_triforce(verts, faces, face_attrs=None): # float[V, ...], float[F, 3] -> ...
  #
  # subdivide each triangle into
  #      /\
  #     /__\
  #    /\  /\
  #   /__\/__\
  #
  assert faces.shape[1] == 3

  V = len(verts)
  neighbor201, neighbor10, _ = process_neighbor20(faces, V)
  neighbor10 = np.uint32(neighbor10)

  E = len(neighbor10)
  F = len(neighbor201)

  new_verts = np.empty_like(verts, shape=(V + E, verts.shape[1]))
  new_faces = np.empty_like(faces, shape=(4 * F, 3))
  if face_attrs is not None:
    new_face_attrs = np.empty_like(face_attrs, shape=(4 * F, ) + face_attrs.shape[1:])
    for i in range(4):
      new_face_attrs[i::4] = face_attrs

  # new verts
  new_verts[:V] = verts
  new_verts[V:] = (verts[neighbor10[:, 0]] + verts[neighbor10[:, 1]]) / 2

  # new faces
  for f, ((v0, e0), (v1, e1), (v2, e2)) in enumerate(neighbor201):
    new_faces[4 * f + 0] = [V + e0, V + e1, V + e2]
    new_faces[4 * f + 1] = [V + e0,     v1, V + e1]
    new_faces[4 * f + 2] = [V + e1,     v2, V + e2]
    new_faces[4 * f + 3] = [V + e2,     v0, V + e0]

  if face_attrs is not None:
    return new_verts, new_faces, new_face_attrs
  return new_verts, new_faces


def subdiv_mobius(verts, faces): # float[V, ...], float[F, 3] -> ...
  #
  # - Subdivide each face into 6 faces from 7 vertices as in
  #       v3
  #     e2   e1
  #       vf
  #  v1   e3   v2
  #
  # - `new_verts` is computed as average
  # - `parity` is reflection parity of (possible) Mobus triangles
  # - See ex81_tiling_sphere.glsl for construction of Mobus triangles (3, 3, 2), (4, 3, 2), (5, 3, 2)
  #
  assert faces.shape[1] == 3

  V = len(verts)

  neighbor201, neighbor10, _ = process_neighbor20(faces, V)
  neighbor10 = np.uint32(neighbor10)

  E = len(neighbor10)
  F = len(neighbor201)

  # Allocate
  new_verts = np.empty_like(verts, shape=(V + E + F, verts.shape[1]))
  new_faces = np.empty_like(faces, shape=(6 * F, 3))
  parity = np.empty(6 * F, dtype=verts.dtype)

  # new verts
  new_verts[:V] = verts
  new_verts[V:][:E] = (verts[neighbor10[:, 0]] + verts[neighbor10[:, 1]]) / 2

  # offset of vertex index
  oE = V
  oF = V + E

  # new faces
  for f, ((v0, e0), (v1, e1), (v2, e2)) in enumerate(neighbor201):
    new_verts[V:][E:][f] = (verts[v0] + verts[v1] + verts[v2]) / 3
    new_faces[6 * f + 0] = [v0, oE + e0, oF + f];  parity[6 * f + 0] = +1
    new_faces[6 * f + 1] = [v1, oE + e1, oF + f];  parity[6 * f + 1] = +1
    new_faces[6 * f + 2] = [v2, oE + e2, oF + f];  parity[6 * f + 2] = +1
    new_faces[6 * f + 3] = [oE + e0, v1, oF + f];  parity[6 * f + 3] = -1
    new_faces[6 * f + 4] = [oE + e1, v2, oF + f];  parity[6 * f + 4] = -1
    new_faces[6 * f + 5] = [oE + e2, v0, oF + f];  parity[6 * f + 5] = -1

  return new_verts, new_faces, parity


def geodesic_subdiv(p_vs, faces):
  p_vs, faces = subdiv_triforce(p_vs, faces)
  return normalize(p_vs), faces


def normalize(v): # float[..., d] -> float[...]
  return v / np.linalg.norm(v, axis=-1, keepdims=True)


# Pick arbitrary vector orthogonal to n
def orthogonal(n): # float[3] -> float[3]
  if abs(n[0]) < 0.9: v = [1, 0, 0]
  else:               v = [0, 1, 0]
  return normalize(np.cross(n, v))


def project_orthogonal(v, n): # (float[..., 3], float[..., 3]) -> float[..., 3]
  # ufunc version of "v - np.dot(v, n) * n"
  return v - np.sum(v * n, axis=-1, keepdims=True) * n


def extrude_line(ps, m=2**5, r=0.5, closed=True): # float[k, 3] -> (float[k * m, 3], uint[?, 4])
  assert ps.shape[1] == 3
  assert closed  # TODO: non closed case (implement data.grid_cylinder)
  k = len(ps)

  # tangents by finite difference
  tangents = normalize(np.roll(ps, -1, axis=0) - np.roll(ps, 1, axis=0))

  # normals
  # TODO: this approach breakdowns for torus knot at the start/end
  # TODO: is this construction related to "parallel transport"?
  normals = np.empty((k, 3), ps.dtype)
  normals[0] = orthogonal(tangents[0])  # arbitrary pick first normal
  for i in range(1, k):
    # other follows by orthogonal project previous normal wrt. tangent
    normals[i] = normalize(project_orthogonal(normals[i - 1], tangents[i]))

  # frame by tangent/normal/normal2
  normals2 = np.cross(normals, tangents)

  # construct faces based on grid topology
  uv, faces = data.grid_torus(k, m)
  u = np.uint32(k * uv[:, 0])    # float[?]     (in {0, 1, .. k - 1})
  v = 2 * np.pi * uv[:, [1]]     # float[?, 1]  (in [0, 2pi))
  p  = ps[u]                     # float[?, 3]
  n1 = normals[u]                # float[?, 3]
  n2 = normals2[u]               # float[?, 3]
  p_vs = p + r * n1 * np.cos(v) + r * n2 * np.sin(v)
  return p_vs, faces


def extrude_line_with_normal_hint(ps, normal_hints, m=2**5, r=0.5, closed=True):
  # (float[k, 3], float[k, 3]) -> (float[k * m, 3], uint[?, 4])
  assert ps.shape[1] == 3
  assert closed  # TODO: non closed case (implement data.grid_cylinder)
  k = len(ps)

  # tangents by finite difference
  tangents = normalize(np.roll(ps, -1, axis=0) - np.roll(ps, 1, axis=0))

  # normal by projecting "normal hint" to orthogonal space of tangent
  normals = normalize(project_orthogonal(normal_hints, tangents))

  # frame by tangent/normal/normal2
  normals2 = np.cross(normals, tangents)

  # construct faces based on grid topology
  uv, faces = data.grid_torus(k, m)
  u = np.uint32(k * uv[:, 0])    # float[?]     (in {0, 1, .. k - 1})
  v = 2 * np.pi * uv[:, [1]]     # float[?, 1]  (in [0, 2pi))
  p  = ps[u]                     # float[?, 3]
  n1 = normals[u]                # float[?, 3]
  n2 = normals2[u]               # float[?, 3]
  p_vs = p + r * n1 * np.cos(v) + r * n2 * np.sin(v)
  return p_vs, faces
