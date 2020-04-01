import numba.pycc
import numpy as np
from . import numba_optim_src

cc = numba.pycc.CC('numba_optim_bin')
cc.verbose = True

for name, sig in numba_optim_src.implementations:
  cc.export(name, sig)(getattr(numba_optim_src, name))

if __name__ == "__main__":
  cc.compile()
