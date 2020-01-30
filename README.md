PySide2 (Qt python binding) based shadertoy-like application

```
# Install dependency
pip install -r requirements.txt

# Run gui
python shader_app.py --width 500 --height 500 shaders/example16.glsl

# Render offscreen
python shader_app.py --width 500 --height 500 shaders/example16.glsl --offscreen shaders/images/example16.png
```
