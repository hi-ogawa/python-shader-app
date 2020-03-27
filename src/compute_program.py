from PySide2 import QtGui
import OpenGL.GL as gl
import math
from .common import ShaderError


COMPUTE_SHADER_TEMPLATE = """
#version 430 core
layout (local_size_x = {local_size[0]}, local_size_y = {local_size[1]}, local_size_z = {local_size[2]}) in;
uniform float iTime;
uniform int iFrame;
uniform vec3 iResolution;
uniform vec4 iMouse;
uniform uint iKey;
uniform uint iKeyModifiers;
{sampler_uniform_decls}
void {name}(uvec3, uvec3 {sampler_arg_decls});
void main() {{
  {name}(gl_GlobalInvocationID, gl_LocalInvocationID {sampler_args});
}}
{src}
"""

class ComputeProgram():
  def __init__(self, config):
    self.program = None
    self.global_size = config['global_size']
    self.local_size = config['local_size']

  def init_resource(self):
    self.program = QtGui.QOpenGLShaderProgram()

  def load_compute_shader(self, src):
    self.program.removeAllShaders()
    success = self.program.addShaderFromSourceCode(QtGui.QOpenGLShader.Compute, src)
    if not success:
      raise ShaderError(f"Compute: \n{self.program.log()}")

    if not self.program.link():
      raise ShaderError(f"Link: \n{self.program.log()}")

  def cleanup(self):
    # QOpenGLShaderProgram's destructor frees resouce
    pass

  def get_group_size(self, W, H):
    gg, ll = self.global_size, self.local_size
    # Handle "eval" mode
    if type(gg) == str: gg = eval(gg, dict(W=W, H=H))
    if type(ll) == str: ll = eval(ll, dict(W=W, H=H))

    return [ math.ceil(g / l) for g, l in zip(gg, ll)]

  def draw(
      self, texture_ids, W, H, frame, time, mouse_down,
      mouse_press_pos, mouse_release_pos, mouse_move_pos,
      key, key_modifiers):
    self.program.bind()

    # Uniform setup (exactly same as `Renderer.draw`)
    gl.glUniform1f(self.program.uniformLocation('iTime'), time)
    gl.glUniform1i(self.program.uniformLocation('iFrame'), frame)
    gl.glUniform3f(self.program.uniformLocation('iResolution'), W, H, W / H)
    gl.glUniform1ui(self.program.uniformLocation('iKey'), key)
    gl.glUniform1ui(self.program.uniformLocation('iKeyModifiers'), key_modifiers)

    for i, texture_id in enumerate(texture_ids):
      gl.glUniform1i(self.program.uniformLocation(f"iSampler{i}"), i)
      gl.glActiveTexture(getattr(gl, f"GL_TEXTURE{i}"))
      gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id)

    mz, mw = mouse_press_pos or (0, H - 1)
    if mouse_down:
      mx, my = mouse_move_pos or (0, H - 1)
      my, mw = [ H - 1 - t for t in [my, mw] ]
    else:
      mx, my = mouse_release_pos or (0, H - 1)
      my, mw = [ H - 1 - t for t in [my, mw] ]
      mz, mw = [ -t for t in [mz, mw] ]
    gl.glUniform4f(self.program.uniformLocation('iMouse'), mx, my, mz, mw)

    # Dispatch call
    gl.glDispatchCompute(*self.get_group_size(W, H))

    # Finalize
    self.program.release()
