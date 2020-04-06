#
# For the proof, see https://gitlab.com/hiogawa/scratch/-/blob/f9078200a420d32162e3f1765f14426a459105f3/python/harmonic_polynomial_v2.ipynb
#
# NOTE:
# - I proved the result for the different set of polynomials from the original paper http://graphics.stanford.edu/papers/envmap/
#   since they actually use "non-harmonic" polynomial.
#
# Usage:
#   python -c 'from misc.hdr.src.irradiance import *; print_M_from_file("shaders/images/hdrihaven/fireplace_1k.hdr")'
#   python -c 'from misc.hdr.src.irradiance import *; make_irradiance_map_from_file("shaders/images/hdrihaven/fireplace_1k.hdr")'
#

import numpy as np


def integrate(g): # float[h, w] -> float[9]
  #
  # Treat 2d array `g` as
  # (0, 0) -> phi
  #    |
  #   \/
  #  theta
  #
  h, w = g.shape
  dtheta = np.pi / h
  dphi   = 2 * np.pi / w

  theta = np.linspace(0, np.pi, num=h, endpoint=False) + dtheta / 2
  phi = np.linspace(0, 2 * np.pi, num=w, endpoint=False) + dphi / 2
  phi, theta = np.meshgrid(phi, theta)

  x = np.sin(theta) * np.cos(phi)
  y = np.sin(theta) * np.sin(phi)
  z = np.cos(theta)
  p0 = 1
  p10 = x
  p11 = y
  p12 = z
  p20 = x * y
  p21 = y * z
  p22 = z * x
  p23 = x**2 - y**2
  p24 = 2 * z**2 - x**2 - y**2
  ps = [p0, p10, p11, p12, p20, p21, p22, p23, p24]

  g_ps = []
  for p in ps:
      integ = dtheta * dphi * np.sum(np.sin(theta) * p * g)
      g_ps.append(integ)
  g_ps = np.array(g_ps)
  return g_ps


def make_M(g): # float[h, w] -> float[4, 4]
  g_ps = integrate(g)
  g_p0 , \
  g_p10, \
  g_p11, \
  g_p12, \
  g_p20, \
  g_p21, \
  g_p22, \
  g_p23, \
  g_p24, = g_ps
  M = np.array([
    (15 * g_p23 - 5 * g_p24) / 64,                    15 * g_p20 / 16, 15 * g_p22 / 16, g_p10 / 2,
                                0, - (15 * g_p23/64 + 5 * g_p24) / 64, 15 * g_p21 / 16, g_p11 / 2,
                                0,                                  0,  5 * g_p24 / 32, g_p12 / 2,
                                0,                                  0,               0,  g_p0 / 4,
  ]).reshape((4, 4))
  return M


def format_M(M): # float[4, 4] -> str
  return """\
{: >10.7f}, {: >10.7f}, {: >10.7f}, {: >10.7f},
{: >10.7f}, {: >10.7f}, {: >10.7f}, {: >10.7f},
{: >10.7f}, {: >10.7f}, {: >10.7f}, {: >10.7f},
{: >10.7f}, {: >10.7f}, {: >10.7f}, {: >10.7f},
""".format(*list(map(float, M.reshape(-1))))


def make_M_from_file(infile):
  from . import main
  rgb = main.load_file(infile)
  return [
    make_M(rgb[..., 0]),
    make_M(rgb[..., 1]),
    make_M(rgb[..., 2]),
  ]


def print_M_from_file(infile):
  import textwrap
  ms = make_M_from_file(infile)
  ms_str = [textwrap.indent(format_M(m)[:-2], '    ') for m in ms]
  return print(f"""\
mat4[3](
  mat4(
{ms_str[0]}
  ),
  mat4(
{ms_str[1]}
  ),
  mat4(
{ms_str[2]}
  )
);\
""")


#
# Generate irradiance map using M for debugging and demonstration
#

def make_irradiance_map_single(g, w, h, clamp_negative=True): # float[h_in, w_in], h, w -> float[h, w]
  M = make_M(g)
  dtheta = np.pi / h
  dphi   = 2 * np.pi / w

  theta = np.linspace(0, np.pi, num=h, endpoint=False) + dtheta / 2
  phi = np.linspace(0, 2 * np.pi, num=w, endpoint=False) + dphi / 2
  phi, theta = np.meshgrid(phi, theta)  # phi, theta : float[h, w]

  x = np.sin(theta) * np.cos(phi)
  y = np.sin(theta) * np.sin(phi)
  z = np.cos(theta)
  n = np.stack([x, y, z, np.ones_like(x)], axis=-1) # float[h, w, 4]
  result = np.empty_like(x)

  for i in range(h):
    for j in range(w):
      result[i, j] = np.dot(n[i, j], M @ n[i, j])  # <- this is the important formula

  if clamp_negative:
    result = np.fmax(0, result)

  return result


def make_irradiance_map(data, w, h, clamp_negative=True): # float[h_in, w_in, k], h, w -> float[h, w, k]
  depth = data.shape[-1]
  result = np.empty((h, w, depth), dtype=data.dtype)
  for i in range(depth):
    result[..., i] = make_irradiance_map_single(data[..., i], w, h, clamp_negative)
  return result


def make_irradiance_map_from_file(infile, outfile=None, clip=None, w=256, h=128):
  from . import main
  if outfile is None:
    outfile = infile + '.irr.hdr'
  rgb = main.load_file(infile)
  if clip is not None:
    rgb = np.fmin(rgb, clip)
  rgb_irr = make_irradiance_map(rgb, w, h)
  main.write_file(outfile, rgb_irr)
