PySide2 (Qt python binding) based shadertoy-like application


Usage:

```
# Install dependencies
pip install -r requirements.txt

# Run gui
python shader_app.py --width 500 --height 500 shaders/example16.glsl

# Render offscreen
python shader_app.py --width 500 --height 500 shaders/example16.glsl --offscreen shaders/images/example16.png

# Render all examples offscreen
python batch.py --out-dir shaders/images --format png shaders/example*.glsl

# Unit test
python -m unittest -v test/*
```
