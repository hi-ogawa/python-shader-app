import numpy as np


def from_svg(x1, y1, r1, r2, rot, large_arc_flag, sweep_flag, x2, y2):
  assert rot == 0
  assert large_arc_flag in [0, 1]
  assert sweep_flag in [0, 1]
  assert r1 == r2
  r = r1
  ccw = sweep_flag == 1
  large = large_arc_flag == 1

  p1 = np.array([x1, y1])
  p2 = np.array([x2, y2])
  pmid = (p1 + p2) / 2
  pdif = p2 - p1

  l = np.linalg.norm(pdif)
  u = np.array([-pdif[1], pdif[0]]) / l
  t = np.arcsin((l / 2) / r)  # angle(p1, center, p2) / 2
  lc = np.cos(t) * r          # dist. from center to pmid

  if (ccw and not large) or (not ccw and large):
    c = pmid + lc * u
  else:
    c = pmid - lc * u

  v1 = p1 - c
  v2 = p2 - c
  t1 = np.arctan2(v1[1], v1[0]) / (2 * np.pi)
  t2 = np.arctan2(v2[1], v2[0]) / (2 * np.pi)
  if ccw:
    t2 = np.mod(t2 - t1, 1) + t1  # t2 in [t1, t1 + 1]
  else:
    t1 = np.mod(t1 - t2, 1) + t2  # t1 in [t2, t2 + 1]

  # Round (1e-5 helps removing -0.0)
  c, t1, t2 = [np.round(_ + 1e-5, decimals=3) for _ in [c, t1, t2]]
  return [c[0], c[1], r, t1, t2]


def check_single(cx, cy, r, t1, t2, _cx, _cy, _r, _t1, _t2):
  dt = t2 - t1
  _dt = _t2 - _t1
  s = np.mod(_t1 - t1, 1)
  return np.allclose([cx, cy, r, dt, s], [_cx, _cy, _r, _dt, 0])


def test(font_svg):
  import re
  with open(font_svg) as f:
    content = f.read()

  for line_num, line in enumerate(content.splitlines()):

    if m := re.match("<path d=\"(.*?)\"", line.strip()):
      tokens = m.group(1).split()

      if tokens[0] == 'M' and tokens[3] == 'A':
        m = re.search("<!-- arc (.*) -->", line.strip())
        assert m, f"'arc' comment not found (L:{line_num})"

        comment_tokens = [float(_) for _ in m.group(1).split()]
        args = [float(_) for _ in [*tokens[1:3], *tokens[4:]]]
        converted = from_svg(*args)
        if not check_single(*converted, *comment_tokens):
          print(f"NON MATCH (L:{line_num})")
          print("in:  ", tokens)
          print("out: ", converted)
          print("ans: ", comment_tokens)
          print()
