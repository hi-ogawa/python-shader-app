import OpenImageIO as oiio
import numpy as np

def solve(p, q, max_iter=2**7, init_eps=1.0, debug=False):
  # assert 0 < b < c
  b = 1 - p
  c = q - p
  #
  # Solve x > 0 s.t. g(x) = exp(b x) - c x - 1 = 0
  # - use Newton method
  # - initial value x0 is taken so that it won't converge to x = 0,
  #   which probably is guaranteed by g'(x0) = b exp(b x0) - c > 0
  #   i.e. x0 > log(c / b) / b
  #
  from math import log, exp
  x = log(c / b) / b + init_eps
  for _ in range(max_iter):
    g  = exp(b * x) - c * x - 1
    dg = b * exp(b * x) - c
    if debug:
      print(f"x: {x:.5f}, g: {g:.5f}")
    x = x - g / dg
    if abs(g) < 0.0000001:
      break
  return x


def make_log_knee_ufunc(p, q):
  #
  # diff-able. conti. f s.t.
  # f(t) = (if      t <= p)  t
  #        (if p <  t <= q)  p + (log(a (t - p) + 1)) / a
  #        (if q <  t     )  1
  #
  # here, trivially:
  #     f (p) = p
  #     f'(p) = (1 / a) * a = 1
  # but,
  #      f(q) = p + (log(a (q - p) + 1)) / a = 1
  # this requires to solve a > 0 s.t.
  #      (q - p) a + 1 = exp((1 - p) a)
  # which unique/exist iff (1 - p) < (q - p)  (i.e. 1 < q)
  #
  assert p < 1.0  # knee low
  assert q > 1.0  # knee hight
  a = solve(p, q)
  def ufunc(t):
    mask = t < p
    y = np.empty_like(t)
    y[ mask] = t[mask]
    y[~mask] = p + np.log(a * (t[~mask] - p) + 1) / a
    y = np.clip(y, 0, 1)
    return y
  return ufunc


def main(infile, outfile, knee_low, knee_high, exposure):
  # Input
  image_input = oiio.ImageInput.open(infile)
  buf = image_input.read_image()

  # Apply tonemap (exposure + log knee curve + gamma)
  buf = buf * (2**exposure)
  buf = make_log_knee_ufunc(knee_low, knee_high)(buf)
  buf = buf**(1 / 2.2)

  # Convert to bytes
  buf = np.clip(buf * 256, 0, 255).astype(np.uint8)

  # Output
  image_output = oiio.ImageOutput.create(outfile)
  image_output.open(outfile, image_input.spec())
  image_output.write_image(buf)
  image_output.close()
