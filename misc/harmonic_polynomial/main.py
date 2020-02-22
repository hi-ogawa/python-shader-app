import sympy
import sympy.codegen.rewriting as sympy_rewriting
import numpy as np
from sympy import I, cos, sin, pi
from sympy.abc import x, y, z, theta, phi


def make_ladder(l):
  # Ladder operator to enumerate harmonic polynomial
  Jx = lambda f: -I * (y * f.diff(z) - z * f.diff(y))
  Jy = lambda f: -I * (z * f.diff(x) - x * f.diff(z))
  L_down = lambda f: Jx(f) - I * Jy(f)

  # Top of the ladder
  ps = [(x + I * y)**l]

  # Go down the ladder
  for _ in range(2 * l):
    ps.append(L_down(ps[-1]).simplify())
  return ps


def make_norm_squares(l):
  # norm square of the top
  a = np.array([sympy.Integer(_) for _ in range(1, l + 1)])
  top = 2 * pi * np.prod((2 * a) / (2 * a + 1)) * 2

  # Go down the ladder
  coeffs = [top]
  for k in range(2 * l):
    coeffs.append(coeffs[-1] * (2 * l - k) * (k + 1))
  return coeffs


def to_legendre_theta(p):
  sub_pairs = [
    [x, sin(theta)],
    [y, 0],
    [z, cos(theta)]]
  return p.subs(sub_pairs)


#
# Generate macro
#

def pow_to_mul(base, exp):
    assert exp >= 1
    if exp == 1:
        return base
    return sympy.Mul(base, pow_to_mul(base, exp - 1), evaluate=False)

pow_to_mul_optim = sympy_rewriting.ReplaceOptim(
    lambda p: p.is_Pow and p.exp.is_Integer,
    lambda p: sympy.UnevaluatedExpr(pow_to_mul(p.base, int(p.exp))))

def preprocess(expr):
  expr = expr.replace(sympy.pi, sympy.symbols('SH_PI'))
  expr = expr.replace(sympy.sin, lambda _: sympy.symbols('SH_SIN_THETA'))
  expr = expr.replace(sympy.cos, lambda _: sympy.symbols('SH_COS_THETA'))
  expr = pow_to_mul_optim(expr)
  return expr

def generate_list(name, exprs):
  result = f"#define {name}(_)"
  for expr in exprs:
    result += f" \\\n  _({sympy.printing.ccode(expr)})"
  return result

def generate_legendre_macro(l):
  ladder = make_ladder(l)
  ladder_norm_squares = make_norm_squares(l)
  ladder_legendre = [to_legendre_theta(_) for _ in ladder]
  ladder_legendre_normalized = [
      sympy.cancel(x / sympy.sqrt(y)) for x, y in zip(ladder_legendre, ladder_norm_squares)]
  return generate_list('SH_LEGENDRE', map(preprocess, ladder_legendre_normalized))
