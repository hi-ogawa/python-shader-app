try:
  from .numba_optim_bin import *

except:
  import sys
  message = "`numba_optim_bin` not found. Using `numba_optim_src` instead."
  print(f"[numba_optim.py] {message}", file=sys.stderr)

  from .numba_optim_src import *
