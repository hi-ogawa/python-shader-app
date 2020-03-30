```
# Precompile numba source (generates e.g. src/numba_optim_bin.cpython-38-x86_64-linux-gnu.so)
python -m src.numba_optim_compile

# Run test
python -m unittest -v src/test.py
```

TODO

- [x] subdivision
- [x] smooth normal
- [x] example mesh
  - 4hedron, 8hedron, 20hedron
- [ ] file loader
  - [x] ply
  - [ ] obj
- [ ] optimize mesh processing
  - python loop free implementation
    - numpy trick or use numba
