import numpy as np;  Np = np.array


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
  new_verts = np.empty_like(verts, shape=(np.prod(faces.shape), verts.shape[1]))
  new_faces = np.empty_like(faces)
  V = 0
  for f, vs in enumerate(faces):
    for i, v in enumerate(vs):
      new_faces[f, i] = V
      new_verts[V] = verts[v]
      V += 1
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


def compute_vertex_normals(p_vs, faces):
  # @params
  #   p_vs:  Np[N, 3]
  #   faces: Np[K, 3]
  # @returns
  #   n_vs:  Np[N, 3]
  n_vs = np.zeros_like(p_vs)  # Np[N, 3]
  for vs in faces:
    ps = [p_vs[v] for v in vs]
    n = np.cross(ps[1] - ps[0], ps[2] - ps[0])
    n /= np.linalg.norm(n)
    for v0 in vs:
      n_vs[v0] = n
  return n_vs


def compute_smooth_vertex_normals(p_vs, faces):
  # @params
  #   p_vs:  Np[N, 3]
  #   faces: Np[K, 3]
  # @returns
  #   n_vs:  Np[N, 3]
  n_vs = np.zeros_like(p_vs)                    # Np[N, 3]
  d_vs = np.zeros(len(p_vs), dtype=p_vs.dtype)  # Np[N]
  for vs in faces:
    ps = [p_vs[v] for v in vs]
    n = np.cross(ps[1] - ps[0], ps[2] - ps[0])
    n /= np.linalg.norm(n)
    for v0 in vs:
      n_vs[v0] += n
      d_vs[v0] += 1
  n_vs = n_vs / d_vs.reshape((-1, 1))  # not normalized
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
