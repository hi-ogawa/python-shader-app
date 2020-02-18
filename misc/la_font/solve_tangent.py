import numpy as np

def pp(result):
  import json
  print(json.dumps(result, indent=2))


def circle_circle(cx1, cy1, r1, cx2, cy2, r2):
  c1 = np.array([cx1, cy1])
  c2 = np.array([cx2, cy2])
  v = c2 - c1
  l = np.linalg.norm(v)
  result = []

  # no tangent
  if l + min(r1, r2) <= max(r1, r2):
    return result

  # 2 tangents
  s = np.arctan2(v[1], v[0])
  ss = np.arccos((r2 - r1) / l)
  for u in [-s + ss, -s - ss]:
    data = {
      "t1": u / (2 * np.pi),
      "p1": list(c1 + r1 * np.array([np.cos(u), np.sin(u)])),
      "t2": u / (2 * np.pi),
      "p2": list(c2 + r2 * np.array([np.cos(u), np.sin(u)])),
    }
    result += [data]

  # 2 more tangents
  if r1 + r2 < l:
    s = np.arctan2(v[1], v[0])
    ss = np.arccos((r1 + r2) / l)
    for t in [ss, -ss]:
      data = {
        "t1": (+s + t) / (2 * np.pi),
        "p1": list(c1 + r1 * np.array([np.cos(+s + t), np.sin(+s + t)])),
        "t2": (-s + t) / (2 * np.pi),
        "p2": list(c2 + r2 * np.array([np.cos(-s + t), np.sin(-s + t)])),
      }
      result += [data]

  return result


def circle_point(cx, cy, r, x, y):
  c = np.array([cx, cy])
  p = np.array([x, y])
  v = p - c
  l = np.linalg.norm(v)

  result = []
  if l <= r:
    return result

  s = np.arctan2(v[1], v[0])
  ss = np.arccos(r / l)
  for t in [s + ss, s - ss]:
    data = {
      "t": t / (2 * np.pi),
      "p": list(c + r * np.array([np.cos(t), np.sin(t)])),
    }
    result += [data]

  return result
