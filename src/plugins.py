from PySide2 import QtGui
import OpenGL.GL as gl
import ctypes
import numpy as np


class Plugin():
  def configure(self, config, src, W, H): pass
  def cleanup(self): pass
  def on_begin_draw(self): pass
  def on_draw(
      self, default_framebuffer, W, H, frame, time, mouse_down,
      mouse_press_pos, mouse_release_pos, mouse_move_pos,
      key, key_modifiers): pass
  def on_end_draw(self): pass


class SsboPlugin(Plugin):
  def configure(self, config, src, W, H):
    self.W, self.H = W, H  # in order to support "eval" for size
    self.config = config
    self.binding = self.config['binding']
    self.ssbo = gl.glGenBuffers(1)
    data, size = self.get_data()
    gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, self.ssbo)
    gl.glBufferData(gl.GL_SHADER_STORAGE_BUFFER, size, data, gl.GL_DYNAMIC_DRAW);
    gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, 0);

  def get_data(self): # -> (data, int)
    typ = self.config['type']
    if typ == 'size':
      size = self.config['size']
      # Handle "eval" mode
      if type(size) == str:
        size = eval(size, dict(W=self.W, H=self.H))
      return ctypes.c_void_p(0), size

    if typ == 'file':
      file = self.config['data']
      bs = open(file, 'rb').read()
      itemsize = self.config.get('align16')
      if itemsize is not None:
        bs = self.pad_data(bs, itemsize, 16)
      return bs, len(bs)

    if typ == 'eval':
      expr = self.config['data']
      bs = eval(expr, dict(np=np))
      return bs, len(bs)

    raise RuntimeError(f"[SsboPlugin] Invalid type : {typ}")

  def pad_data(self, data, itemsize, alignsize): # (bytes, int, int) -> bytes
    pad = (alignsize - itemsize) % alignsize
    a = np.frombuffer(data, dtype=np.uint8)
    a = a.reshape((-1, itemsize))
    a = np.pad(a, ((0, 0), (0, pad)))
    return a.tobytes()

  def cleanup(self):
    gl.glDeleteBuffers(1, self.ssbo)

  def on_begin_draw(self):
    gl.glBindBufferBase(gl.GL_SHADER_STORAGE_BUFFER, self.binding, self.ssbo);

  def on_end_draw(self):
    gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, 0);


# Quick-and-dirty usual rasterizer OpenGL pipeline as plugin
class RasterPlugin(Plugin):
  def configure(self, config, src, W, H):
    self.config = config
    self.setup_vao()
    self.setup_program(src)

  def cleanup(self):
    self.vao.destroy()
    self.program.removeAllShaders()

  def setup_vao(self):
    self.vao = QtGui.QOpenGLVertexArrayObject()
    self.vao.create()

  def setup_program(self, src):
    self.program = QtGui.QOpenGLShaderProgram()
    vs_name = self.config['vertex_shader']
    vs_src = '\n'.join([
      '#version 430 core',
      f"#define COMPILE_{vs_name}",
      src,
    ])
    vs_success = self.program.addShaderFromSourceCode(QtGui.QOpenGLShader.Vertex, vs_src)
    if not vs_success:
      raise RuntimeError(f"[VertexPlugin] Vertex: \n{self.program.log()}")

    fs_name = self.config['fragment_shader']
    fs_src = '\n'.join([
      '#version 430 core',
      f"#define COMPILE_{fs_name}",
      src,
    ])
    fs_success = self.program.addShaderFromSourceCode(QtGui.QOpenGLShader.Fragment, fs_src)
    if not fs_success:
      raise RuntimeError(f"[VertexPlugin] Fragment: \n{self.program.log()}")

    if not self.program.link():
      raise RuntimeError(f"[VertexPlugin] Link: \n{self.program.log()}")

  def on_draw(
      self, default_framebuffer, W, H, frame, time, mouse_down,
      mouse_press_pos, mouse_release_pos, mouse_move_pos,
      key, key_modifiers):

    # Bind
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, default_framebuffer)
    self.program.bind()
    self.vao.bind()
    gl.glViewport(0, 0, W, H)

    # Enable capabilites
    last_capabilities = []
    for capability in self.config.get('capabilities', []):
      last_capabilities += [gl.glIsEnabled(getattr(gl, capability))]
      gl.glEnable(getattr(gl, capability))

    # Blend setting
    if self.config.get('blend'):
      gl.glEnable(gl.GL_BLEND)
      gl.glBlendEquation(gl.GL_FUNC_ADD)
      gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

    # Set uniform
    gl.glUniform1f(self.program.uniformLocation('iTime'), time)
    gl.glUniform1i(self.program.uniformLocation('iFrame'), frame)
    gl.glUniform3f(self.program.uniformLocation('iResolution'), W, H, W / H)
    gl.glUniform1ui(self.program.uniformLocation('iKey'), key)
    gl.glUniform1ui(self.program.uniformLocation('iKeyModifiers'), key_modifiers)

    mz, mw = mouse_press_pos or (0, H - 1)
    if mouse_down:
      mx, my = mouse_move_pos or (0, H - 1)
      my, mw = [ H - 1 - t for t in [my, mw] ]
    else:
      mx, my = mouse_release_pos or (0, H - 1)
      my, mw = [ H - 1 - t for t in [my, mw] ]
      mz, mw = [ -t for t in [mz, mw] ]
    gl.glUniform4f(self.program.uniformLocation('iMouse'), mx, my, mz, mw)

    count = self.config['count']
    if type(count) == str:
      count = eval(count)
    gl.glUniform1ui(self.program.uniformLocation('iVertexCount'), count)

    # Draw call
    primitive = getattr(gl, self.config['primitive'])
    gl.glDrawArrays(primitive, 0, count)

    # Reset capabilites
    for last, capability in zip(last_capabilities, self.config.get('capabilities', [])):
      if not last:
        gl.glDisable(getattr(gl, capability))

    gl.glDisable(gl.GL_BLEND)

    # Release
    self.vao.release()
    self.program.release()
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0)
