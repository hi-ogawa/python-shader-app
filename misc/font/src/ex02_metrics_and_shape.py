#
# Drawing glyph metrics and shape
#

import numpy as np
import matplotlib
import matplotlib.pyplot as plt
from . import stbtt


def binomial_coeffs(n): # -> float(n+1)
  from math import factorial
  a = np.arange(n + 1); a[0] = 1
  i = np.cumprod(a)
  j = np.flip(i)
  return factorial(n) / (i * j)


def bezier_interp(xs, d, num=8): # float(d+1) -> float(num)
  assert len(xs) == d + 1
  t = np.linspace(0, 1, num=num)         # float(num)
  bc = binomial_coeffs(d)                # float(d+1)
  a = np.arange(d + 1)                   # float(d+1)
  s1 = (1 - t) ** (d - a[:, np.newaxis]) # float(d+1, num)
  s2 = t ** a[:, np.newaxis]             # float(d+1, num)
  return (np.array(xs) * bc) @ (s1 * s2)


def plot_aabb(ax, xm, ym, xM, yM, origin=[0, 0], **kwargs):
  ox, oy = origin
  xs = np.array([xm, xM, xM, xm, xm]) + ox
  ys = np.array([ym, ym, yM, yM, ym]) + oy
  ax.plot(xs, ys, **kwargs)


def plot_shape(ax, vertices, origin=[0, 0]):
  ox, oy = origin

  # support only move/line/curve (not cubic)
  assert all([v.type[0] in [1, 2, 3] for v in vertices])

  def get_points(ty, x='x', y='y'):
    def gen():
      for v in vertices:
        if v.type[0] == ty:
          yield [getattr(v, x) + ox, getattr(v, y) + oy]
    points = list(gen())
    if len(points) > 0:
      return np.array(points).T
    return [[], []]

  # control points
  ax.scatter(*get_points(1), s=64, marker='s', facecolors='none', edgecolors='C1', label='move')
  ax.scatter(*get_points(2), s=64, marker='v', c='C1', label='line')
  ax.scatter(*get_points(3), s=64, marker='*', c='C1', label='cuve')
  ax.scatter(*get_points(3, x='cx', y='cy'), s=64/4, marker='x', c='C1', label='cuve-ctl')

  # contour line
  for v in vertices:
    ty = v.type[0]
    assert ty in [1, 2, 3]
    if ty == 1: # move
      pass
    if ty == 2: # line
      xs = np.array([last_x, v.x])
      ys = np.array([last_y, v.y])
      ax.plot(xs + ox, ys + oy, color='C4')
    if ty == 3: # curve (2deg bezier)
      xs = bezier_interp([last_x, v.cx, v.x], 2)
      ys = bezier_interp([last_y, v.cy, v.y], 2)
      ax.plot(xs + ox, ys + oy, color='C5')
    last_x, last_y = v.x, v.y


def plot_glyph(ax, metrics, vertices, origin=[0, 0]):
  # bbox
  plot_aabb(
      ax, *[metrics[n] for n in ['x_min', 'y_min', 'x_max', 'y_max']], origin,
      color='C0', linestyle='--', label='bbox')

  # bearing/advance
  ox, oy = origin
  ylim = ax.get_ylim()
  ax.plot(
      [metrics['bearing'] + ox] * 2, ylim,
      color='C2', linestyle='--', label='bearing')
  ax.plot(
      [metrics['advance'] + ox] * 2, ylim,
      color='C3', linestyle='--', label='advance')

  # glyph contour
  plot_shape(ax, vertices, origin)


def plot(fontfile, codepoints, kerning=True):
  ctx = stbtt.StbttContext()
  ctx.load_font(fontfile)
  glyph_indices = [ctx.get_glyph_index(c) for c in codepoints]

  # Prepare plot canvas
  fig, ax = plt.subplots()
  ax.axis('equal')
  ax.grid()
  ax.set(ylim=[-600, 2100])

  # Plot each glyph
  origin = [0, 0]
  for i, glyph_index in enumerate(glyph_indices):
    # Obtain glyph data (metrics and ontline vertices)
    metrics = ctx.get_glyph_metrics(glyph_index)
    vertices = ctx.get_glyph_shape(glyph_index)

    # Plot data
    plot_glyph(ax, metrics, vertices, origin)

    # Move origin based on "advance" and "kerning"
    origin[0] += metrics['advance']
    if kerning and i + 1 < len(glyph_indices):
      origin[0] += ctx.get_glyph_kern_advance(glyph_index, glyph_indices[i+1])

  ax.set(xlim=[-500, origin[0] + 500])
  return fig


def main(fontfile, codepoints, outfile, outsize, legend=False, kerning=True):
  matplotlib.use('agg')
  fig = plot(fontfile, codepoints, kerning=kerning)
  fig.set(dpi=100, size_inches=np.array(outsize) / 100)
  if legend:
    fig.axes[0].legend()
  fig.savefig(outfile)
  plt.close(fig)
