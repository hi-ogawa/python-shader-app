Objectives

- Render offscreen from container

I was curious how much Qt can run in container or real offscreen environment.
It seems "AA_UseSoftwareOpenGL" might not be supported on linux,
or maybe I'm not setting up mesa right.
Anyways, I haven't investigated this enough yet.

```
# Enter container shell and run app
$ (sudo) docker-compose run dev bash
> python3 -m pip install -r requirements.txt
> python3 -m unittest -v src/*_test.py
> QT_QPA_PLATFORM=offscreen python3 -m src.app --width 500 --height 500 shaders/ex00_checker.glsl --offscreen test.png
```
