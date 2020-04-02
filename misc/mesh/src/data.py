import numpy as np;  Np = np.array


# cube [-1, 1]^3
def cube():
  p_vs = Np([
    0, 0, 0,
    1, 0, 0,
    1, 1, 0,
    0, 1, 0,
    0, 0, 1,
    1, 0, 1,
    1, 1, 1,
    0, 1, 1,
  ], np.float32).reshape((-1, 3))
  p_vs = 2 * p_vs - 1

  faces = Np([
    0, 3, 2, 1,
    0, 1, 5, 4,
    1, 2, 6, 5,
    2, 3, 7, 6,
    3, 0, 4, 7,
    4, 5, 6, 7,
  ], np.uint32).reshape((-1, 4))

  return p_vs, faces


# 4 corners of cube [-1, 1]^3
def hedron4():
  p_vs = Np([
    0, 0, 0,
    1, 1, 0,
    0, 1, 1,
    1, 0, 1,
  ], np.float32).reshape((-1, 3))
  p_vs = 2 * p_vs - 1

  faces = Np([
    0, 2, 1,
    0, 3, 2,
    0, 1, 3,
    1, 2, 3,
  ], np.uint32).reshape((-1, 3))

  return p_vs, faces


# face centers of cube [-1, 1]^3
def hedron8():
  p_vs = Np([
    +1, 0, 0,
     0,+1, 0,
     0, 0,+1,
     0,-1, 0,
     0, 0,-1,
    -1, 0, 0,
  ], np.float32).reshape((-1, 3))

  faces = Np([
    0, 1, 2,
    0, 2, 3,
    0, 3, 4,
    0, 4, 1,
    5, 2, 1,
    5, 3, 2,
    5, 4, 3,
    5, 1, 4,
  ], np.uint32).reshape((-1, 3))

  return p_vs, faces


# icosahedron with circumsphere |x| = 1
def hedron20():
  # apply spherical-cosine rule to equilateral-triangle-piramid
  #   cos(t) = cos(t)^2 + sin(t)^2 cos(p)
  #   => (1 - cos(p)) * cos(t)^2 - cos(t) + cos(p) = 0
  #   => cos(t) = cos(p) / (1 - cos(p))  (or 1)
  p = 2 * np.pi / 5
  t = np.arccos(np.cos(p) / (1 - np.cos(p)))
  theta = [
    0,
    *([        t] * 5),
    *([np.pi - t] * 5),
    np.pi
  ]
  phi   = [
    0,
    *(p * np.arange(5)        ),
    *(p * np.arange(5) + p / 2),
    0,
  ]

  p_vs = np.stack([
    np.sin(theta) * np.cos(phi),
    np.sin(theta) * np.sin(phi),
    np.cos(theta)
  ]).T
  p_vs = Np(p_vs, np.float32)

  faces = Np([
    0, 1, 2,
    0, 2, 3,
    0, 3, 4,
    0, 4, 5,
    0, 5, 1,

    2, 1, 6,
    3, 2, 7,
    4, 3, 8,
    5, 4, 9,
    1, 5,10,

    6, 7, 2,
    7, 8, 3,
    8, 9, 4,
    9,10, 5,
   10, 6, 1,

    7, 6, 11,
    8, 7, 11,
    9, 8, 11,
   10, 9, 11,
    6,10, 11,
  ], np.uint32).reshape((-1, 3))

  return p_vs, faces


# hedron20 as dual of hedron12
def hedron12():
  p_vs, faces = hedron20()

  # dual verts as center of three original verts
  new_p_vs = (p_vs[faces[:, 0]] + p_vs[faces[:, 1]] + p_vs[faces[:, 2]]) / 3
  new_p_vs /= np.linalg.norm(new_p_vs[0])  # project to unit sphere

  # dual faces
  # 1. gather neighbors
  neighbor0200 = [[] for _ in range(len(p_vs))]
  for f, vs in enumerate(faces):
    for v, v_prev, v_next in zip(vs, np.roll(vs, 1, axis=0), np.roll(vs, -1, axis=0)):
      neighbor0200[v].append((f, v_next, v_prev))

  # 2. sort neighbors in ccw
  def sort(n200): # List[(f, (v0, v1))]
    new_n200 = [n200.pop()]
    while len(n200) > 0:
      _, _, v1 = new_n200[-1]
      found = next(filter(lambda fv0v1: fv0v1[1] == v1, n200))
      n200.remove(found)
      new_n200.append(found)
    return new_n200

  new_faces = [[] for _ in range(len(p_vs))]
  for v, n200 in enumerate(neighbor0200):
    n200 = sort(n200)
    new_faces[v] = [f for f, _, _ in n200]
  assert all(len(vs) == 5 for vs in new_faces)

  new_faces = Np(new_faces, np.uint32)
  return new_p_vs, new_faces
