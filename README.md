PySide2 (Qt python binding) based shadertoy-like application


Usage:

```
# Install dependencies
pip install -r requirements.txt

# Run gui
python -m src.app --width 500 --height 500 shaders/ex00_checker.glsl

# Render offscreen
python -m src.app --width 500 --height 500 shaders/ex00_checker.glsl --offscreen test.png

# Render all examples offscreen
python -m src.batch --out-dir shaders/images --format png shaders/ex*.glsl

# Unit test
python -m unittest -v src/*_test.py

# Download shader from shadertoy
python -m shaders.shadertoy.download --out-dir shaders/shadertoy https://www.shadertoy.com/view/Xds3zN
```
