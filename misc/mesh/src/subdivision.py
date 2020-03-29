import numpy as np


def find_if(ls, predicate):
  return next(filter(predicate, ls))


def min_max(i, j):
  return min(i, j), max(i, j)


def check_no_boundary(neighbor20, nV):
  neighbor00 = [[] for _ in range(nV)] # adjacency list

  # 1st pass: enumerate unique edges by filtering face-ccw vertex pair
  for vs in neighbor20:
    for v0, v1 in zip(vs, np.roll(vs, -1, axis=0)):
      neighbor00[v0].append(v1)

  # 2nd pass
  for v0, vs in enumerate(neighbor00):
    for v1 in vs:
      # edge v0-v1 has two neighbor faces  iff  v0 in neighbor00[v1]
      if not v0 in neighbor00[v1]:
        return False
  return True


def process_neighbor20(neighbor20, nV): # -> (neighbor201, neighbor10, vertex_deg)
  assert check_no_boundary(neighbor20, nV)

  neighbor001 = [[] for _ in range(nV)]  # "directed (v0 < v1)" adjacency list
  neighbor10  = []
  vertex_deg  = [0 for _ in range(nV)]
  nE = 0

  # 1st pass: enumerate unique edges by filtering face-ccw vertex pair
  for vs in neighbor20:
    for v0, v1 in zip(vs, np.roll(vs, -1, axis=0)):
      vertex_deg[v0] += 1

      # NOTE: if there's boundary, such edge might not be counted here
      if v0 < v1:
        neighbor001[v0].append((v1, nE))  # current nE as "edge id"
        neighbor10.append((v0, v1))
        nE += 1

  # 2nd pass: extend neighbor20 to include edge id
  nF = len(neighbor20)
  neighbor201 = [[] for _ in range(nF)]
  for f, vs in enumerate(neighbor20):
    for v0, v1 in zip(vs, np.roll(vs, -1, axis=0)):
      v_m, v_M = min_max(v0, v1)
      _, e = find_if(neighbor001[v_m], lambda v_e: v_e[0] == v_M)
      neighbor201[f].append((v0, e))

  return neighbor201, neighbor10, vertex_deg


def subdivision(vertex_data, neighbor20): # -> (vertex_data', neighbor20')
  nV = len(vertex_data)
  nF = len(neighbor20)

  # "0th pass"
  neighbor201, neighbor10, vertex_deg = process_neighbor20(neighbor20, nV)
  nE = len(neighbor10)

  # Number of new vertices = #V + #E + #F
  new_vertex_data = np.zeros((nV + nE + nF,) + vertex_data.shape[1:])
  new_neighbor20 = []

  # Offset of edge/face point data within new vertices
  oE = nV
  oF = nV + nE

  # Single face traversal implementation of Catmull-Clerk subdiv
  for f, ves in enumerate(neighbor201):
    # make face point data
    f_data = sum([vertex_data[v] for v, e in ves]) / len(ves)
    new_vertex_data[oF + f] = f_data

    for (v0, e0), (v1, e1) in zip(ves, np.roll(ves, -1, axis=0)):
      # new face by "f -> e0 -> v1 -> e1"
      new_neighbor20.append([oF + f, oE + e0, v1, oE + e1])

      #
      # accumulate data between face/edge/vert
      #

      # (face -> edge)
      new_vertex_data[oE + e0] += f_data / 4

      # (vert -> edge)
      new_vertex_data[oE + e0] += vertex_data[v0] / 4

      # (face -> vert)
      n = vertex_deg[v0]
      new_vertex_data[v0] += f_data / n**2

      # (vert -> vert)
      new_vertex_data[v0] += vertex_data[v1] / n**2

      # (vert -> vert (self))
      new_vertex_data[v0] += (n - 2) * vertex_data[v0] / n**2

  return new_vertex_data, new_neighbor20
