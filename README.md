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
python -m src.download --key $(cat shadertoy.key) Xds3zN > shaders/shadertoy/Xds3zN.glsl

# Download shadertoy's builtin textures
python -c 'import src.texture; src.texture.shadertoy_download_all("shaders/images/shadertoy")'
```
