from PySide2 import QtCore, QtGui, QtUiTools
import OpenGL.GL as gl
import os, ctypes, dataclasses
import numpy as np
from .common import ShaderError
from .utils import reload_rec, exec_config, exec_config_if_str, if3


def pad_data(data, itemsize, alignsize): # (bytes, int, int) -> bytes
  pad = (alignsize - itemsize) % alignsize
  a = np.frombuffer(data, dtype=np.uint8)
  a = a.reshape((-1, itemsize))
  a = np.pad(a, ((0, 0), (0, pad)))
  return a.tobytes()


@dataclasses.dataclass
class PluginConfigureArg:
  config: dict
  src: str
  W: int
  H: int
  offscreen: bool


class Plugin():
  def configure(self, arg : PluginConfigureArg): pass
  def cleanup(self): pass
  def on_bind_program(self, program_handle): pass
  def on_begin_draw(self): pass
  def on_draw(
      self, default_framebuffer, W, H, frame, time, mouse_down,
      mouse_press_pos, mouse_release_pos, mouse_move_pos,
      key, key_modifiers, plugins): pass
  def on_end_draw(self): pass


class SsboPlugin(Plugin):
  def configure(self, arg):
    self.W, self.H = arg.W, arg.H  # in order to support "eval" for size
    self.config = arg.config
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
  def configure(self, arg):
    self.config = arg.config
    self.exec     = self.config['exec']
    self.bindings = self.config['bindings']
    N = len(self.bindings)
    self.align16s = self.config.get('align16', [16] * N)
    self.ssbos = [gl.glGenBuffers(1) for _ in range(N)]
    self.setup_data()

  def setup_data(self):
    ls_data = exec_config(self.exec)  # List[bytes]

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
  def configure(self, arg):
    self.config = arg.config
    self.setup_vao()
    self.setup_program(arg.src)

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
      key, key_modifiers, plugins):

    # Bind
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, default_framebuffer)
    self.program.bind()
    self.vao.bind()
    gl.glViewport(0, 0, W, H)

    # TODO: for now it's so adhoc
    for plugin in plugins:
      plugin.on_bind_program(self.program.programId())

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
  def configure(self, arg):
    self.config = arg.config
    self.vertex_data, self.index_data = exec_config(self.config['exec'])  # (bytes, bytes)
    self.setup_program(arg.src)
    self.setup_vao()

  def cleanup(self):
    self.vertex_buffer.destroy()
    self.index_buffer.destroy()
    self.vao.destroy()
    self.program.removeAllShaders()

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

    gs_name = self.config.get('geometry_shader')
    if gs_name:
      gs_src = '\n'.join([
        '#version 430 core',
        '#define COMPILE_' + gs_name,
        src,
      ])
      gs_success = self.program.addShaderFromSourceCode(QtGui.QOpenGLShader.Geometry, gs_src)
      if not gs_success:
        raise ShaderError(f"[RasterscriptPlugin] Geometry: \n{self.program.log()}")

    if not self.program.link():
      raise ShaderError(f"[RasterscriptPlugin] Link: \n{self.program.log()}")

  def on_draw(
      self, default_framebuffer, W, H, frame, time, mouse_down,
      mouse_press_pos, mouse_release_pos, mouse_move_pos,
      key, key_modifiers, plugins):

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

    # TODO: for now it's so adhoc
    for plugin in plugins:
      plugin.on_bind_program(self.program.programId())

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
    if type(instance_count) == str:
      instance_count = eval(instance_count)
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


# TODO: Migrate texture support from app.py to this plugin
class TexturePlugin(Plugin):
  def configure(self, arg):
    self.config = arg.config
    self.file = self.config.get('file') or exec_config(self.config['file_exec'])
    self.handle = TexturePlugin.create_image(
        self.file, self.config.get('y_flip'))
    TexturePlugin.configure_texture(self.handle, self.config)

  def cleanup(self):
    gl.glDeleteTextures(self.handle)

  @staticmethod
  def create_image(file, y_flip):
    if file.endswith('.hdr'):
      return TexturePlugin.create_image_hdr(file, y_flip)
    return TexturePlugin.create_image_default(file, y_flip)

  @staticmethod
  def create_image_hdr(file, y_flip):
    # Use my hdr loader
    import misc.hdr.src.main_v2 as main
    with open(file, 'rb') as f:
      data = main.load(f)  # float32[h, w, 3]
    if y_flip:
      data = np.flip(data, axis=0)

    # Allocate gl resource
    handle = gl.glGenTextures(1)
    gl.glBindTexture(gl.GL_TEXTURE_2D, handle)
    H, W = data.shape[:2]
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D, 0, gl.GL_RGB32F, W, H, 0,
        gl.GL_RGB, gl.GL_FLOAT, data)
    gl.glBindTexture(gl.GL_TEXTURE_2D, 0)
    return handle

  @staticmethod
  def create_image_default(file, y_flip):
    qimage = QtGui.QImage(file)
    if y_flip:
      qimage = qimage.mirrored(False, True)  # flip y direction
    qimage_format = qimage.format()
    assert qimage_format != QtGui.QImage.Format_Invalid
    if qimage_format != QtGui.QImage.Format_RGBA8888:
      qimage = qimage.convertToFormat(QtGui.QImage.Format_RGBA8888)

    # Allocate gl resource
    handle = gl.glGenTextures(1)
    gl.glBindTexture(gl.GL_TEXTURE_2D, handle)
    W, H = qimage.width(), qimage.height()
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8, W, H, 0,
        gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, qimage.constBits())
    gl.glBindTexture(gl.GL_TEXTURE_2D, 0)
    return handle

  @staticmethod
  def configure_texture(handle, config):
    # Setup mipmap-level, filter-mode, wrap-mode
    gl.glBindTexture(gl.GL_TEXTURE_2D, handle)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S,
        gl.GL_REPEAT if config['wrap'] == 'repeat' else gl.GL_CLAMP_TO_EDGE)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T,
        gl.GL_REPEAT if config['wrap'] == 'repeat' else gl.GL_CLAMP_TO_EDGE)
    if config['filter'] == 'linear':
      min_filter = gl.GL_LINEAR_MIPMAP_LINEAR if config['mipmap'] else gl.GL_LINEAR
      mag_filter = gl.GL_LINEAR
    else:
      min_filter = gl.GL_NEAREST_MIPMAP_NEAREST if config['mipmap'] else gl.GL_NEAREST
      mag_filter = gl.GL_NEAREST
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, min_filter)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, mag_filter)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_BASE_LEVEL, 0)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAX_LEVEL, 10)
    if config['mipmap']:
      gl.glGenerateMipmap(gl.GL_TEXTURE_2D)
    gl.glBindTexture(gl.GL_TEXTURE_2D, 0)

  def on_bind_program(self, program_handle):
    location = gl.glGetUniformLocation(program_handle, self.config['name'])
    index = self.config['index']
    gl.glUniform1i(location, index)
    gl.glActiveTexture(getattr(gl, f"GL_TEXTURE{index}"))
    gl.glBindTexture(gl.GL_TEXTURE_2D, self.handle)


class CubemapPlugin(Plugin):
  SUB_TARGETS = [
    gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X,
    gl.GL_TEXTURE_CUBE_MAP_POSITIVE_Y,
    gl.GL_TEXTURE_CUBE_MAP_POSITIVE_Z,
    gl.GL_TEXTURE_CUBE_MAP_NEGATIVE_X,
    gl.GL_TEXTURE_CUBE_MAP_NEGATIVE_Y,
    gl.GL_TEXTURE_CUBE_MAP_NEGATIVE_Z,
  ]

  def configure(self, arg):
    self.config = arg.config
    self.setup_cubemap()

  def cleanup(self):
    gl.glDeleteTextures(self.handle)

  def setup_cubemap(self):
    self.handle = gl.glGenTextures(1)
    target = gl.GL_TEXTURE_CUBE_MAP
    gl.glBindTexture(target, self.handle)
    for file, sub_target in zip(self.config['files'], CubemapPlugin.SUB_TARGETS):
      CubemapPlugin.setup_cubemap_data(file, sub_target)
    CubemapPlugin.setup_cubemap_parameters(target, self.config)
    gl.glBindTexture(target, 0)

  # TODO: refactor with TexturePlugin
  @staticmethod
  def setup_cubemap_data(file, sub_target):
    qimage = QtGui.QImage(file)
    qimage_format = qimage.format()
    assert qimage_format != QtGui.QImage.Format_Invalid
    if qimage_format != QtGui.QImage.Format_RGBA8888:
      qimage = qimage.convertToFormat(QtGui.QImage.Format_RGBA8888)
    W, H = qimage.width(), qimage.height()
    gl.glTexImage2D(
        sub_target, 0, gl.GL_RGBA8, W, H, 0,
        gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, qimage.constBits())

  @staticmethod
  def setup_cubemap_parameters(target, config):
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE)
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE)
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_R, gl.GL_CLAMP_TO_EDGE)
    gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER,
        if3(config.get('filter') == 'linear', gl.GL_LINEAR_MIPMAP_LINEAR, gl.GL_NEAREST))
    gl.glTexParameteri(target, gl.GL_TEXTURE_MAG_FILTER,
        if3(config.get('filter') == 'linear', gl.GL_LINEAR, gl.GL_NEAREST))
    if config.get('mipmap'):
      gl.glTexParameteri(target, gl.GL_TEXTURE_BASE_LEVEL, 0)
      gl.glTexParameteri(target, gl.GL_TEXTURE_MAX_LEVEL, 10)
      gl.glGenerateMipmap(target)

  def on_bind_program(self, program_handle):
    location = gl.glGetUniformLocation(program_handle, self.config['name'])
    index = self.config['index']
    gl.glUniform1i(location, index)
    gl.glActiveTexture(getattr(gl, f"GL_TEXTURE{index}"))
    gl.glBindTexture(gl.GL_TEXTURE_CUBE_MAP, self.handle)
    gl.glEnable(gl.GL_TEXTURE_CUBE_MAP_SEAMLESS)


# TODO:
# - support vector data
# - close this window when main window is closed
# - trigger render (i.e. MyWidget.update) when value changed
class UniformPlugin(Plugin):
  def configure(self, arg):
    # config params: name, default, min, max, resolution
    self.config = arg.config
    self.offscreen = arg.offscreen
    self.resolution = self.config.get('resolution', 100)
    self.default = exec_config_if_str(self.config['default'])
    if not self.offscreen:
      self.setup_gui()
      self.set_value(self.default)

  def cleanup(self):
    if not self.offscreen:
      self.window.close()

  def setup_gui(self):
    filename = os.path.join(os.path.dirname(__file__), 'uniform_plugin.ui')
    data = QtCore.QByteArray(open(filename, 'rb').read())
    buffer = QtCore.QBuffer(data)
    self.window = QtUiTools.QUiLoader().load(buffer)
    self.window.setWindowTitle(self.config['name'])
    self.slider = self.window.findChild(QtCore.QObject, 'horizontalSlider')
    self.label = self.window.findChild(QtCore.QObject, 'label')
    self.slider.setRange(
        self.config['min'] * self.resolution,
        self.config['max'] * self.resolution)
    self.slider.valueChanged.connect(
        lambda *_: self.label.setText(f"{self.get_value(): >4.2f}"))

    # Quick trick to prevent this window from appearing before the main window
    QtCore.QTimer.singleShot(500, lambda *_: self.window.show())

  def set_value(self, v):
    return self.slider.setValue(v * self.resolution)

  def get_value(self):
    if not self.offscreen:
      return self.slider.value() / self.resolution
    return self.default

  def on_bind_program(self, program_handle):
    location = gl.glGetUniformLocation(program_handle, self.config['name'])
    gl.glUniform1f(location, self.get_value())
