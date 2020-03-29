from PySide2 import QtGui
import OpenGL.GL as gl
import ctypes
import numpy as np
from .common import ShaderError
from .utils import reload_rec


def pad_data(data, itemsize, alignsize): # (bytes, int, int) -> bytes
  pad = (alignsize - itemsize) % alignsize
  a = np.frombuffer(data, dtype=np.uint8)
  a = a.reshape((-1, itemsize))
  a = np.pad(a, ((0, 0), (0, pad)))
  return a.tobytes()


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
        bs = pad_data(bs, itemsize, 16)
      return bs, len(bs)

    if typ == 'eval':
      expr = self.config['data']
      bs = eval(expr, dict(np=np))
      return bs, len(bs)

    raise ShaderError(f"[SsboPlugin] Invalid type : {typ}")

  def cleanup(self):
    gl.glDeleteBuffers(1, self.ssbo)

  def on_begin_draw(self):
    gl.glBindBufferBase(gl.GL_SHADER_STORAGE_BUFFER, self.binding, self.ssbo)

  def on_end_draw(self):
    gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, 0)
    gl.glMemoryBarrier(gl.GL_SHADER_STORAGE_BARRIER_BIT)


class SsboscriptPlugin(Plugin):
  def configure(self, config, src, W, H):
    self.config = config
    self.exec     = config['exec']
    self.bindings = config['bindings']
    N = len(self.bindings)
    self.align16s = config.get('align16', [16] * N)
    self.ssbos = [gl.glGenBuffers(1) for _ in range(N)]
    self.setup_data()

  def setup_data(self):
    exec_ns = dict(RESULT=None)
    exec(self.exec, exec_ns)
    ls_data = exec_ns['RESULT']  # List[bytes]

    for data, align16, ssbo in zip(ls_data, self.align16s, self.ssbos):
      data = pad_data(data, align16, 16)
      gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, ssbo)
      gl.glBufferData(gl.GL_SHADER_STORAGE_BUFFER, len(data), data, gl.GL_DYNAMIC_DRAW);
      gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, 0);

  def cleanup(self):
    for ssbo in self.ssbos:
      gl.glDeleteBuffers(1, ssbo)

  def on_begin_draw(self):
    for binding, ssbo in zip(self.bindings, self.ssbos):
      gl.glBindBufferBase(gl.GL_SHADER_STORAGE_BUFFER, binding, ssbo)

  def on_end_draw(self):
    gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, 0)
    gl.glMemoryBarrier(gl.GL_SHADER_STORAGE_BARRIER_BIT)


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
      raise ShaderError(f"[RasterPlugin] Vertex: \n{self.program.log()}")

    fs_name = self.config['fragment_shader']
    fs_src = '\n'.join([
      '#version 430 core',
      f"#define COMPILE_{fs_name}",
      src,
    ])
    fs_success = self.program.addShaderFromSourceCode(QtGui.QOpenGLShader.Fragment, fs_src)
    if not fs_success:
      raise ShaderError(f"[RasterPlugin] Fragment: \n{self.program.log()}")

    if not self.program.link():
      raise ShaderError(f"[RasterPlugin] Link: \n{self.program.log()}")

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


# TODO: no more copy&paste
class RasterscriptPlugin(Plugin):
  def configure(self, config, src, W, H):
    self.config = config
    self.exec_script()
    self.setup_program(src)
    self.setup_vao()

  def cleanup(self):
    self.vertex_buffer.destroy()
    self.index_buffer.destroy()
    self.vao.destroy()
    self.program.removeAllShaders()

  def exec_script(self):
    exec_ns = dict(RESULT=None, RELOAD_REC=reload_rec)
    exec(self.config['exec'], exec_ns)
    self.vertex_data, self.index_data = exec_ns['RESULT']  # (bytes, bytes)

  def setup_vao(self):
    self.vao = QtGui.QOpenGLVertexArrayObject()
    self.vertex_buffer = QtGui.QOpenGLBuffer(QtGui.QOpenGLBuffer.VertexBuffer)
    self.index_buffer = QtGui.QOpenGLBuffer(QtGui.QOpenGLBuffer.IndexBuffer)
    self.vao.create()
    self.vertex_buffer.create()
    self.index_buffer.create()

    self.vertex_buffer.bind()
    self.vertex_buffer.allocate(self.vertex_data, len(self.vertex_data))
    self.vertex_buffer.release()

    self.index_buffer.bind()
    self.index_buffer.allocate(self.index_data, len(self.index_data))
    self.index_buffer.release()

    self.vao.bind()
    self.vertex_buffer.bind()
    for name, args_str in self.config['vertex_attributes'].items():
      self.program.enableAttributeArray(name)
      self.program.setAttributeBuffer(name, *eval(args_str))
    self.vertex_buffer.release()
    self.vao.release()

  def setup_program(self, src):
    self.program = QtGui.QOpenGLShaderProgram()
    vs_src = '\n'.join([
      '#version 430 core',
      '#define COMPILE_' + self.config['vertex_shader'],
      src,
    ])
    vs_success = self.program.addShaderFromSourceCode(QtGui.QOpenGLShader.Vertex, vs_src)
    if not vs_success:
      raise ShaderError(f"[RasterscriptPlugin] Vertex: \n{self.program.log()}")

    fs_src = '\n'.join([
      '#version 430 core',
      '#define COMPILE_' + self.config['fragment_shader'],
      src,
    ])
    fs_success = self.program.addShaderFromSourceCode(QtGui.QOpenGLShader.Fragment, fs_src)
    if not fs_success:
      raise ShaderError(f"[RasterscriptPlugin] Fragment: \n{self.program.log()}")

    if not self.program.link():
      raise ShaderError(f"[RasterscriptPlugin] Link: \n{self.program.log()}")

  def on_draw(
      self, default_framebuffer, W, H, frame, time, mouse_down,
      mouse_press_pos, mouse_release_pos, mouse_move_pos,
      key, key_modifiers):

    # Bind
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, default_framebuffer)
    self.program.bind()
    self.vao.bind()
    self.index_buffer.bind()
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

    # Draw call
    primitive = getattr(gl, self.config['primitive'])
    instance_count = self.config.get('instance_count', 1)
    gl.glDrawElementsInstanced(
        primitive, len(self.index_data), gl.GL_UNSIGNED_INT,
        ctypes.c_void_p(0), instance_count)

    # Reset capabilites
    for last, capability in zip(last_capabilities, self.config.get('capabilities', [])):
      if not last:
        gl.glDisable(getattr(gl, capability))

    gl.glDisable(gl.GL_BLEND)

    # Release
    self.vao.release()
    self.program.release()
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0)
