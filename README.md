PySide2 (Qt python binding) based shadertoy-like application


Usage:

```
# Install dependencies
pip install -r requirements.txt

# Run gui
python shader_app.py --width 500 --height 500 shaders/ex00_checker.glsl

# Render offscreen
python shader_app.py --width 500 --height 500 shaders/ex00_checker.glsl --offscreen test.png

# Render all examples offscreen
python batch.py --out-dir shaders/images --format png shaders/ex*.glsl

# Unit test
python -m unittest discover -t . -s test -v
```
