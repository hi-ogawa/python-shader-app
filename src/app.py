from PySide2 import QtCore, QtGui, QtWidgets, QtUiTools
import OpenGL.GL as gl
import pydash
import os, array, ctypes, time, collections
from .utils import \
    exit_app_on_exception, setup_interrupt_handler, setup_qt_message_handler, \
    preprocess_include, PreprocessIncludeWatcher, parse_shader_config, \
    handle_OpenGL_debug_message
from .plugins import SsboPlugin
from .compute_program import ComputeProgram, COMPUTE_SHADER_TEMPLATE


VERTEX_SHADER_SOURCE = """
#version 430 core
layout (location = 0) in vec2 vert_position_;
void main() {
  gl_Position = vec4(vert_position_, 0.0, 1.0);
}
"""

VERTEX_DATA = array.array('f', [
  -1.0, -1.0,
   1.0, -1.0,
   1.0,  1.0,
  -1.0,  1.0,
])

INDEX_DATA = array.array('H', [
  2, 0, 1,
  0, 2, 3,
])

# For QOpenGLShaderProgram.setAttributeBuffer(location, type, offset, tuplesize, stride)
VERTEX_SPEC = {
  'vert_position_': (gl.GL_FLOAT, 0, 2, 2 * 4),
}

class ShaderError(RuntimeError):
  pass

class Renderer():
  def __init__(self):
    self.program = None
    self.vao = None
    self.vertex_buffer = None
    self.index_buffer = None

  def init_resource(self):
    self.program = QtGui.QOpenGLShaderProgram()
    self.vao = QtGui.QOpenGLVertexArrayObject()
    self.vertex_buffer = QtGui.QOpenGLBuffer(QtGui.QOpenGLBuffer.VertexBuffer)
    self.index_buffer = QtGui.QOpenGLBuffer(QtGui.QOpenGLBuffer.IndexBuffer)
    self.vao.create()
    self.vertex_buffer.create()
    self.index_buffer.create()

    self.vertex_buffer.bind()
    self.vertex_buffer.allocate(VERTEX_DATA, VERTEX_DATA.itemsize * len(VERTEX_DATA))
    self.vertex_buffer.release()

    self.index_buffer.bind()
    self.index_buffer.allocate(INDEX_DATA, INDEX_DATA.itemsize * len(INDEX_DATA))
    self.index_buffer.release()

  def load_fragment_shader(self, complete_src):
    self.program.removeAllShaders()
    vs_success = self.program.addShaderFromSourceCode(QtGui.QOpenGLShader.Vertex, VERTEX_SHADER_SOURCE)
    if not vs_success:
      raise ShaderError(f"Vertex: \n{self.program.log()}")

    fs_success = self.program.addShaderFromSourceCode(QtGui.QOpenGLShader.Fragment, complete_src)
    if not fs_success:
      raise ShaderError(f"Fragment: \n{self.program.log()}")

    if not self.program.link():
      raise ShaderError(f"Link: \n{self.program.log()}")

    self.setup_vertex_spec()

  def setup_vertex_spec(self):
    self.vao.bind()
    self.vertex_buffer.bind()
    for attrib, args in VERTEX_SPEC.items():
      self.program.enableAttributeArray(attrib)
      self.program.setAttributeBuffer(attrib, *args)
    self.vertex_buffer.release()
    self.vao.release()

  def cleanup(self):
    for resource in [self.vao, self.vertex_buffer, self.index_buffer]:
      resource.destroy()

  def draw(self, texture_ids, W, H, frame, time, mouse_down,
       mouse_press_pos, mouse_release_pos, mouse_move_pos):
    # State setup
    gl.glViewport(0, 0, W, H)

    self.program.bind()
    self.vao.bind()
    self.index_buffer.bind()

    # Uniform setup
    gl.glUniform1f(self.program.uniformLocation('iTime'), time)
    gl.glUniform1i(self.program.uniformLocation('iFrame'), frame)
    gl.glUniform3f(self.program.uniformLocation('iResolution'), W, H, W / H)

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

    # Draw call
    gl.glDrawElements(gl.GL_TRIANGLES, len(INDEX_DATA), gl.GL_UNSIGNED_SHORT, ctypes.c_void_p(0))

    # Finalize
    self.index_buffer.release()
    self.vao.release()
    self.program.release()


DEFAULT_CONFIG = {
  'samplers': [],
  'programs': [ { 'name': 'mainImage', 'output': '$default', 'samplers': [] } ],
  'offscreen_option': { 'fps': 60, 'num_frames': 1 }
}

FRAGMENT_SHADER_TEMPLATE = """
#version 430 core
uniform float iTime;
uniform int iFrame;
uniform vec3 iResolution;
uniform vec4 iMouse;
layout (location = 0) out vec4 iMainFragColor;
{sampler_uniform_decls}
void {name}(out vec4, vec2 {sampler_arg_decls});
void main() {{
  {name}(iMainFragColor, vec2(gl_FragCoord) {sampler_args});
}}
{src}
"""

MyImage = collections.namedtuple('MyImage', [
  'qimage', # QtGui.QImage
  'handle'  # GLuint (OpenGL texture handle)
])

class MultiPassRenderer():
  def __init__(self):
    self.config = None     # dict (cf. parse_shader_config)
    self.renderers = {}    # map<str, Renderer>
    self.framebuffers = {} # map<str, (QOpenGLFramebufferObject, QOpenGLFramebufferObject)>
    self.images = {}       # map<str, MyImage>
    self.plugins = []      # list<Plugin>

  def cleanup(self):
    self.cleanup_renderers()
    self.cleanup_images()
    self.cleanup_framebuffers()
    self.config = None

  def cleanup_renderers(self):
    for renderer in self.renderers.values():
      renderer.cleanup()
    self.renderers = {}

  def cleanup_images(self):
    for image in self.images.values():
      gl.glDeleteTextures(image.handle)
    self.images = {}

  def cleanup_framebuffers(self):
    self.framebuffers = {} # Default destructor frees gl resource

  def cleanup_plugins(self):
    for plugin in self.plugins:
      plugin.cleanup()
    self.plugins = []

  def configure(self, src, W, H):
    self.config = parse_shader_config(src)
    if self.config is None:
      print(f"[MultiPassRenderer] Configuration not found. Use default configuration.")
      self.config = DEFAULT_CONFIG
    print(f"[MultiPassRenderer] Current configuration\n{self.config}")
    self.configure_plugins(self.config.get('plugins', []), W, H)
    self.configure_samplers(W, H)
    self.configure_programs(src)

  # TODO: remove unnecessary re-configure when reloading .glsl
  # TODO: passing "W, H" feels so ad-hoc
  def configure_plugins(self, plugins_config, W, H):
    self.cleanup_plugins()
    for plugin_config in plugins_config:
      name = plugin_config['type']
      params = plugin_config['params']
      klass_name = name.capitalize() + 'Plugin'
      plugin = globals()[klass_name]()
      plugin.configure(params, W, H)
      self.plugins += [plugin]

  def configure_samplers(self, W, H):
    self.cleanup_framebuffers()
    self.cleanup_images()

    for sampler in self.config['samplers']:
      name = sampler['name']
      assert sampler['type'] in ['file', 'framebuffer']
      if sampler['type'] == 'file':
        assert sampler['file']
        image = self.create_image(sampler['file'])
        self.configure_gl_texture(image.handle, sampler)
        self.images[name] = image

      if sampler['type'] == 'framebuffer':
        w, h = (W, H) if sampler['size'] == '$default' else sampler['size']
        fbo_pair = self.create_fbo_pair(
            w, h, sampler['mipmap'],
            sampler.get('internal_format', 'GL_RGBA8'),
            sampler.get('double_buffering', True))
        for fbo in fbo_pair:
          self.configure_gl_texture(fbo.texture(), sampler)
        self.framebuffers[name] = fbo_pair

  def create_image(self, filename):
    # TODO: Support .hdr texture (cf. stb_image)

    # Load image file via QImage
    qimage = QtGui.QImage(filename)
    qimage = qimage.mirrored(False, True) # flip y direction
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
    return MyImage(qimage=qimage, handle=handle)

  def create_fbo_pair(self, W, H, mipmap, internal_format, double_buffering):
    fbo_format = QtGui.QOpenGLFramebufferObjectFormat()
    fbo_format.setMipmap(mipmap)
    fbo_format.setInternalTextureFormat(getattr(gl, internal_format))
    if double_buffering:
      fbo_pair = [QtGui.QOpenGLFramebufferObject(W, H, fbo_format) for _ in range(2)]
    else:
      # NOTE:
      # Support no automatic double buffering for manual render pass acceleration.
      # To reuse our code for double buffering, we use list with identical two elememnts.
      fbo_pair = [QtGui.QOpenGLFramebufferObject(W, H, fbo_format)] * 2
    return fbo_pair

  def configure_gl_texture(self, handle, sampler_config):
    # Setup mipmap-level, filter-mode, wrap-mode
    gl.glBindTexture(gl.GL_TEXTURE_2D, handle)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S,
        gl.GL_REPEAT if sampler_config['wrap'] == 'repeat' else gl.GL_CLAMP_TO_EDGE)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T,
        gl.GL_REPEAT if sampler_config['wrap'] == 'repeat' else gl.GL_CLAMP_TO_EDGE)
    if sampler_config['filter'] == 'linear':
      min_filter = gl.GL_LINEAR_MIPMAP_NEAREST if sampler_config['mipmap'] else gl.GL_LINEAR
      mag_filter = gl.GL_LINEAR
    else:
      min_filter = gl.GL_NEAREST_MIPMAP_NEAREST if sampler_config['mipmap'] else gl.GL_NEAREST
      mag_filter = gl.GL_NEAREST
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, min_filter)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, mag_filter)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_BASE_LEVEL, 0)
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAX_LEVEL, 10)
    if sampler_config['mipmap'] and sampler_config['type'] == 'file':
      gl.glGenerateMipmap(gl.GL_TEXTURE_2D)
    gl.glBindTexture(gl.GL_TEXTURE_2D, 0)

  def configure_programs(self, src):
    # cleanup first
    for renderer in self.renderers.values():
      renderer.cleanup()
    self.renderers = {}

    # validate and setup programs
    # TODO: Refactor API for Renderer and ComputeProgram
    for program in self.config['programs']:
      for sampler_name in program['samplers']:
        assert sampler_name in list(self.framebuffers.keys()) + list(self.images.keys())

      N = len(program['samplers'])
      sampler_uniform_decls = ''.join(f"uniform sampler2D iSampler{i};\n" for i in range(N))
      sampler_arg_decls     = ''.join(f", sampler2D" for i in range(N))
      sampler_args          = ''.join(f", iSampler{i}" for i in range(N))

      if program.get('type') == 'compute':
        # Setup ComputeProgram
        self.renderers[program['name']] = renderer = ComputeProgram(program)
        renderer.init_resource()
        complete_src_attrs = dict(
          src=src, name=program['name'],
          sampler_uniform_decls = sampler_uniform_decls,
          sampler_arg_decls     = sampler_arg_decls[2:],
          sampler_args          = sampler_args[2:],
          local_size            = program['local_size'])
        complete_src = COMPUTE_SHADER_TEMPLATE.format(**complete_src_attrs)
        renderer.load_compute_shader(complete_src)

      else:
        # Setup Renderer
        assert program['output'] in (['$default'] + list(self.framebuffers.keys()))
        self.renderers[program['name']] = renderer = Renderer()
        renderer.init_resource()
        complete_src_attrs = dict(
          src=src, name=program['name'],
          sampler_uniform_decls = sampler_uniform_decls,
          sampler_arg_decls     = sampler_arg_decls,
          sampler_args          = sampler_args)
        complete_src = FRAGMENT_SHADER_TEMPLATE.format(**complete_src_attrs)
        renderer.load_fragment_shader(complete_src)

  def on_begin_draw(self):
    for plugin in self.plugins:
      plugin.on_begin_draw()

  def on_end_draw(self):
    for plugin in self.plugins:
      plugin.on_end_draw()

  def draw_program_substep(self, program, default_framebuffer, W, H, frame, time, mouse_down,
       mouse_press_pos, mouse_release_pos, mouse_move_pos):
    texture_ids = []
    for sampler_name in program['samplers']:
      sampler = pydash.find(self.config['samplers'], {'name': sampler_name})
      if sampler['type'] == 'file':
        handle = self.images[sampler_name].handle

      if sampler['type'] == 'framebuffer':
        fbo_pair = self.framebuffers[sampler_name]
        handle = fbo_pair[0].texture()
        gl.glBindTexture(gl.GL_TEXTURE_2D, handle)
        gl.glGenerateMipmap(gl.GL_TEXTURE_2D)
        gl.glBindTexture(gl.GL_TEXTURE_2D, 0)

      texture_ids.append(handle)

    if not program.get('type') == 'compute':
      if program['output'] == '$default':
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, default_framebuffer)
      else:
        fbo_pair = self.framebuffers[program['output']]
        fbo_pair[1].bind()

    renderer = self.renderers[program['name']]
    renderer.draw(
      texture_ids, W, H, frame, time, mouse_down,
      mouse_press_pos, mouse_release_pos, mouse_move_pos)

  # default_framebuffer : GLuint (e.g. QOpenGLFramebufferObject.handle(), QOpenGLWidget.defaultFramebufferObject())
  # TODO: fold all arguments into dataclass
  def draw(self, default_framebuffer, W, H, frame, time, mouse_down,
       mouse_press_pos, mouse_release_pos, mouse_move_pos):
    # Callback for plugins
    self.on_begin_draw()

    # Global substep mode
    global_substep = self.config.get('substep')
    if global_substep:
      self.draw_global_substep_mode(
          global_substep, default_framebuffer, W, H, frame, time, mouse_down,
          mouse_press_pos, mouse_release_pos, mouse_move_pos)
      return

    # Default mode
    self.draw_default_mode(
        default_framebuffer, W, H, frame, time, mouse_down,
        mouse_press_pos, mouse_release_pos, mouse_move_pos)

    # Callback for plugins
    self.on_end_draw()

  def draw_default_mode(self, default_framebuffer, W, H, frame, time, mouse_down,
       mouse_press_pos, mouse_release_pos, mouse_move_pos):
    for program in self.config['programs']:
      self.draw_program_substep(program, default_framebuffer, W, H, frame, time, mouse_down,
          mouse_press_pos, mouse_release_pos, mouse_move_pos)

    # Swap double buffers
    for pair in self.framebuffers.values():
      pair[0], pair[1] = pair[1], pair[0]

  def draw_global_substep_mode(self, global_substep,
      default_framebuffer, W, H, frame, time, mouse_down,
      mouse_press_pos, mouse_release_pos, mouse_move_pos):
    global_substep = self.config.get('substep')
    num_iter = global_substep['num_iter']
    schedule = global_substep['schedule']

    # Iterate substep scedule
    # TODO: provide someway for program to know substep (e.g. "iSubstepFrame")
    for i in range(global_substep['num_iter']):
      for task in schedule:
        if task['type'] == 'program':
          program = pydash.find(self.config['programs'], {'name': task['name']})
          self.draw_program_substep(
              program, default_framebuffer, W, H, frame, time, mouse_down,
              mouse_press_pos, mouse_release_pos, mouse_move_pos)

        if task['type'] == 'sampler':
          pair = self.framebuffers[task['name']]
          pair[0], pair[1] = pair[1], pair[0]

    # Iterate "non-substep" program (it should be only window render pass)
    for program in self.config['programs']:
      if not program.get('substep'):
        self.draw_program_substep(
            program, default_framebuffer, W, H, frame, time, mouse_down,
            mouse_press_pos, mouse_release_pos, mouse_move_pos)


class MyWidget(QtWidgets.QOpenGLWidget):
  def __init__(self, fragment_shader_file, play_mode, parent=None):
    super(MyWidget, self).__init__(parent)
    self.renderer = MultiPassRenderer()
    self.fragment_shader_file = fragment_shader_file
    self.preprocess_watcher = PreprocessIncludeWatcher(self.fragment_shader_file)

    self.gl_ready = False
    self.shader_error = None

    # TODO: organize time/frame refresh logic (e.g. for reload shader, resize, gui time slider etc...)
    self.full_throttle = play_mode
    self.app_time = 0                          # float \in [0, app_time_maximum]
    self.last_full_throttle_epoch_time = None  # float
    self.app_time_maximum = 20                 # float
    self.delta_times = []                      # [float] last 30 paintGL call intervals
    self.app_frame = 0                         # int \in [0, +oo)

    self.mouse_down = False
    self.mouse_press_pos = None
    self.mouse_release_pos = None
    self.mouse_move_pos = None

  # override
  def mousePressEvent(self, event):
    self.mouse_down = True
    self.mouse_press_pos = self.mouse_move_pos = (event.x(), event.y())
    self.update()

  # override
  def mouseReleaseEvent(self, event):
    self.mouse_down = False
    self.mouse_release_pos = (event.x(), event.y())
    self.update()

  # override
  def mouseMoveEvent(self, event):
    self.mouse_move_pos = (event.x(), event.y())
    self.update()

  # override
  @exit_app_on_exception
  def initializeGL(self):
    self.enable_debug()
    self.load_fragment_shader_file()
    self.preprocess_watcher.changed.connect(self.load_fragment_shader_file)
    self.gl_ready = True

  # override
  def resizeGL(self, W, H):
    self.renderer.configure_samplers(W, H) # TODO: reconfigure only framebuffers (not images)
    self.init_frame()

  # override
  @exit_app_on_exception
  def paintGL(self):
    if self.gl_ready and not self.shader_error:
      self.renderPre()
      self.render()
      self.renderPost()

  def init_frame(self):
    # Render twice for making multipass shader dev easier with pausing
    # (usually initialize at iFrame = 0 and do something at iFrame > 0)
    self.makeCurrent()
    self.app_frame = 0
    self.paintGL()
    self.paintGL()
    self.doneCurrent()
    self.update()


  def load_fragment_shader_file(self):
    self.makeCurrent()
    try:
      src, _ = preprocess_include(self.fragment_shader_file)
      self.renderer.configure(src, self.width(), self.height())
      self.shader_error = None
    except ShaderError as e:
      self.shader_error = e
    self.last_full_throttle_epoch_time = None
    self.init_frame()
    self.doneCurrent()

  def enable_debug(self):
    logger = QtGui.QOpenGLDebugLogger(self)
    assert logger.initialize()
    logger.messageLogged.connect(handle_OpenGL_debug_message)
    logger.startLogging()

  def cleanup(self): # not used
    self.makeCurrent()
    self.renderer.cleanup()
    self.doneCurrent()

  def renderPre(self):
    now_epoch_time = time.time()
    if self.last_full_throttle_epoch_time is None:
      self.last_full_throttle_epoch_time = now_epoch_time

    if self.full_throttle:
      delta = now_epoch_time - self.last_full_throttle_epoch_time
      self.app_time += delta
      if delta > 0:
        self.delta_times = (self.delta_times + [delta])[-30:]
      if self.app_time > self.app_time_maximum:
        self.app_time_maximum *= 2

    self.last_full_throttle_epoch_time = now_epoch_time

  def render(self):
    self.renderer.draw(
      self.defaultFramebufferObject(),
      self.width(), self.height(), self.app_frame, self.app_time,
      self.mouse_down, self.mouse_press_pos,
      self.mouse_release_pos, self.mouse_move_pos)

  def renderPost(self):
    self.app_frame += 1
    if self.full_throttle:
      self.update() # schedule next repaint

  def set_full_throttle(self, value):
    if not self.full_throttle and value:
      self.last_full_throttle_epoch_time = None
      self.update()
    self.full_throttle = value

  def sec_per_frame(self):
    size = len(self.delta_times)
    return sum(self.delta_times) / size if size > 0 else 0


# file : str -> widget : QWidget
def load_ui_file(file):
  loader = QtUiTools.QUiLoader()
  file = QtCore.QFile(file)
  assert file.open(QtCore.QFile.ReadOnly)
  widget = loader.load(file)
  file.close()
  return widget


def setup_gui(fragment_shader_file, w, h, x, y, play_mode):
  # TODO: Temporary inline class/instance
  self = type('MyWindow', (object,), {})()
  self.window = load_ui_file(os.path.join(os.path.dirname(__file__), 'app.ui'))
  self.start_icon = QtGui.QIcon.fromTheme('media-playback-start-symbolic')
  self.pause_icon = QtGui.QIcon.fromTheme('media-playback-pause-symbolic')

  # Add widgets not in .ui file
  self.widget = MyWidget(fragment_shader_file, play_mode=play_mode)
  self.dialog = QtWidgets.QMessageBox() # shader error dialog

  # Grab children from .ui file
  names = ['main_container', 'sub_container', 'dummy', 'button', 'slider', 'label1', 'label2', 'label3', 'label4']
  for name in names:
    setattr(self, name, self.window.findChild(QtCore.QObject, name))

  # Patch up widgets
  self.dummy.close()
  self.main_container.addWidget(self.widget)
  self.main_container.removeWidget(self.dummy)
  self.button._current_icon = None  # for custom dirty checking
  self.label2.setValidator(QtGui.QDoubleValidator())
  self.dialog.setText("[Shader Error]")
  self.dialog.setStandardButtons(QtWidgets.QMessageBox.Close)

  # Setup handlers
  self.slider_resolution = 20

  def update_gui():
    self.slider.setRange(0, self.widget.app_time_maximum * self.slider_resolution)
    self.slider.setValue(self.widget.app_time * self.slider_resolution)
    self.label1.setText(f"{self.widget.app_time: >5.2f}")
    if not self.label2.hasFocus():
      self.label2.setText(f"{self.widget.app_time_maximum: >5.2f}")
    self.label3.setText(f"{self.widget.sec_per_frame() * 1000: >5.2f} (ms/f)")
    self.label4.setText(f"{self.widget.width()}x{self.widget.height()}")

    # QIcon doesn't have equality, so we need to do equality check by ourselves
    # in order to prevent unnecessarily repaint
    next_icon = self.pause_icon if self.widget.full_throttle else self.start_icon
    if self.button._current_icon is not next_icon:
      self.button.setIcon(next_icon)
      self.button._current_icon = next_icon

    if self.widget.shader_error:
      self.dialog.setInformativeText(str(self.widget.shader_error))
      self.dialog.show()
    else:
      self.dialog.close()

  def handle_button_clicked(*_):
    self.widget.set_full_throttle(not self.widget.full_throttle)
    update_gui()

  def handle_slider_changed(*_):
    v = self.slider.value() / self.slider_resolution
    if self.slider.isSliderDown() and v < self.widget.app_time_maximum:
      self.widget.app_time = v
      self.widget.init_frame()
      update_gui()

  def handle_lineedit_finished(*_):
    self.widget.app_time_maximum = float(self.label2.text())
    self.window.setFocus()
    update_gui()

  self.widget.frameSwapped.connect(update_gui)
  self.button.clicked.connect(handle_button_clicked)
  self.slider.valueChanged.connect(handle_slider_changed)
  self.label2.editingFinished.connect(handle_lineedit_finished)
  update_gui()

  # Quick trick to force initial size of GL Window
  self.window.resize(w, h)
  self.widget.setMinimumSize(w, h)
  QtCore.QTimer.singleShot(0, lambda *_: self.widget.setMinimumSize(1, 1))

  self.window.show()
  return self


class OffscreenRenderer():
  def __init__(self, width, height):
    self.w, self.h = width, height
    self.surface = QtGui.QOffscreenSurface()
    self.surface.create()
    self.context = QtGui.QOpenGLContext()
    self.context.create()
    self.context.makeCurrent(self.surface)
    self.fbo = QtGui.QOpenGLFramebufferObject(self.w, self.h)
    self.renderer = MultiPassRenderer()

  def render(self, shader_file):
    src, _ = preprocess_include(shader_file)
    self.renderer.configure(src, self.w, self.h)
    option = self.renderer.config['offscreen_option']
    fps = option['fps']
    num_frames = option['num_frames']
    for frame in range(num_frames):
      time = frame / fps
      self.renderer.draw(
          self.fbo.handle(), self.w, self.h, frame, time, mouse_down=False,
          mouse_press_pos=None, mouse_release_pos=None, mouse_move_pos=None)


def render_offscreen(shader_file, output_file, w, h):
  renderer = OffscreenRenderer(w, h)
  renderer.render(shader_file)
  renderer.fbo.toImage().save(output_file)


def setup_gl_version():
  surface_format = QtGui.QSurfaceFormat()
  surface_format.setMajorVersion(4)
  surface_format.setMinorVersion(3)
  surface_format.setProfile(QtGui.QSurfaceFormat.CoreProfile)
  surface_format.setOption(QtGui.QSurfaceFormat.DebugContext)
  QtGui.QSurfaceFormat.setDefaultFormat(surface_format)


def setup_misc():
  setup_gl_version()
  # Suppress multiline warning
  setup_qt_message_handler(truncate_multiline=True)
  # Suppress Qt's warning (Qt WebEngine seems to be initialized from a plugin. Please set Qt::AA_ShareOpenGLContexts ...)
  QtCore.QCoreApplication.setAttribute(QtCore.Qt.AA_ShareOpenGLContexts)


def run_app(fragment_shader_file, offscreen_output_file, w, h, x=2**7, y=2**7, play_mode=True):
  setup_misc()
  app = QtWidgets.QApplication.instance() or QtWidgets.QApplication()
  if offscreen_output_file:
    render_offscreen(fragment_shader_file, offscreen_output_file, w, h)
  else:
    window = setup_gui(fragment_shader_file, w, h, x, y, play_mode)
    setup_interrupt_handler(app)
    app.exec_()


def main():
  import argparse
  parser = argparse.ArgumentParser(description='ShaderApp')
  parser.add_argument('file', type=str, help='glsl fragment shader file (cf. shaders/example0.glsl)')
  parser.add_argument('--width',  type=int, default=2**9 * 5//4, help='resolution width')
  parser.add_argument('--height', type=int, default=2**9,        help='resolution height')
  parser.add_argument('--offscreen', type=str, default=None,     help='offscreen render output file')
  parser.add_argument('--paused', action='store_true', default=False, help='start app as paused mode')
  args = parser.parse_args()
  run_app(args.file, args.offscreen, args.width, args.height, play_mode=not args.paused)


if __name__ == '__main__':
  main()
