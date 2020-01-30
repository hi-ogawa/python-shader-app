from PySide2 import QtCore, QtGui, QtWidgets, QtUiTools
import OpenGL.GL as gl
import array
import ctypes
import time
from shader_app_utils import \
  exit_app_on_exception, setup_interrupt_handler, setup_qt_message_handler, \
  preprocess_include, PreprocessIncludeWatcher, parse_shader_config


VERTEX_SHADER_SOURCE = """
#version 330
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
#version 330
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

# NOTE:
# - QOpenGLFramebufferObject's texture parameter is GL_RGBA8 and no-mipmap by default.
class MultiPassRenderer():
  def __init__(self):
    self.config = None     # dict (cf. parse_shader_config)
    self.renderers = {}    # map<str, Renderer>
    self.framebuffers = {} # map<str, (QOpenGLFramebufferObject, QOpenGLFramebufferObject)>

  def cleanup(self):
    for renderer in self.renderers.values():
      renderer.cleanup()
    for framebuffer in self.framebuffers.values():
      pass # Default destructor handles freeing resource
    self.renderers = {}
    self.framebuffers = {}
    self.config = None

  def configure(self, src, W, H):
    self.config = parse_shader_config(src)
    if self.config is None:
      print(f"[MultiPassRenderer] Configuration not found. Use default configuration.")
      self.config = DEFAULT_CONFIG

    self.configure_framebuffers(W, H)
    self.configure_programs(src)

  def configure_framebuffers(self, W, H):
    # cleanup first (QOpenGLFramebufferObject's default destructor handles freeing resource)
    self.framebuffers = {}

    # validate allocate double buffers
    for sampler in self.config['samplers']:
      assert sampler['type'] == 'framebuffer' # currently framebuffer only
      fbo_format = QtGui.QOpenGLFramebufferObjectFormat()
      self.framebuffers[sampler['name']] = [
        QtGui.QOpenGLFramebufferObject(W, H, fbo_format),
        QtGui.QOpenGLFramebufferObject(W, H, fbo_format)]

  def configure_programs(self, src):
    # cleanup first
    for renderer in self.renderers.values():
      renderer.cleanup()
    self.renderers = {}

    # validate and setup programs
    for program in self.config['programs']:
      assert program['output'] == '$default' or \
           program['output'] in self.framebuffers.keys()
      for sampler_name in program['samplers']:
        assert sampler_name in self.framebuffers.keys()
      self.renderers[program['name']] = renderer = Renderer()
      renderer.init_resource()
      N = len(program['samplers'])
      complete_src_attrs = dict(
        src=src, name=program['name'],
        sampler_uniform_decls=''.join(f"uniform sampler2D iSampler{i};\n" for i in range(N)),
        sampler_arg_decls=    ''.join(f", sampler2D" for i in range(N)),
        sampler_args=         ''.join(f", iSampler{i}" for i in range(N)))
      complete_src = FRAGMENT_SHADER_TEMPLATE.format(**complete_src_attrs)
      renderer.load_fragment_shader(complete_src)

  # @param default_framebuffer : GLuint (e.g. QOpenGLFramebufferObject.handle(), QOpenGLWidget.defaultFramebufferObject())
  def draw(self, default_framebuffer, W, H, frame, time, mouse_down,
       mouse_press_pos, mouse_release_pos, mouse_move_pos):
    # Draw for each program
    for program in self.config['programs']:
      texture_ids = []
      for sampler_name in program['samplers']:
        texture_ids.append(self.framebuffers[sampler_name][0].texture())

      if program['output'] == '$default':
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, default_framebuffer)
      else:
        self.framebuffers[program['output']][1].bind()

      renderer = self.renderers[program['name']]
      renderer.draw(
        texture_ids, W, H, frame, time, mouse_down,
        mouse_press_pos, mouse_release_pos, mouse_move_pos)

    # Swap double buffers
    for pair in self.framebuffers.values():
      pair[0], pair[1] = pair[1], pair[0]


class MyWidget(QtWidgets.QOpenGLWidget):
  def __init__(self, fragment_shader_file, parent=None):
    super(MyWidget, self).__init__(parent)
    self.renderer = MultiPassRenderer()
    self.fragment_shader_file = fragment_shader_file
    self.preprocess_watcher = PreprocessIncludeWatcher(self.fragment_shader_file)

    self.gl_ready = False
    self.shader_error = None

    # TODO: organize time/frame refresh logic (e.g. for reload shader, resize, gui time slider etc...)
    self.full_throttle = True
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
    self.renderer.configure_framebuffers(W, H)
    self.app_frame = 0

  # override
  @exit_app_on_exception
  def paintGL(self):
    if self.gl_ready and not self.shader_error:
      self.renderPre()
      self.render()
      self.renderPost()

  def load_fragment_shader_file(self):
    self.makeCurrent()
    try:
      src, _ = preprocess_include(self.fragment_shader_file)
      self.renderer.configure(src, self.width(), self.height())
      self.shader_error = None
    except ShaderError as e:
      self.shader_error = e
    self.last_full_throttle_epoch_time = None
    self.app_frame = 0
    self.update()
    self.doneCurrent()

  def enable_debug(self):
    logger = QtGui.QOpenGLDebugLogger(self)
    assert logger.initialize()
    logger.messageLogged.connect(
      lambda m: print("[QOpenGLDebugLogger] ", m.message()))
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


def setup_gui(fragment_shader_file, w, h, x, y):
  # TODO: Temporary inline class/instance
  self = type('MyWindow', (object,), {})()
  self.window = load_ui_file('shader_app.ui')
  self.start_icon = QtGui.QIcon.fromTheme('media-playback-start-symbolic')
  self.pause_icon = QtGui.QIcon.fromTheme('media-playback-pause-symbolic')

  # Add widgets not in .ui file
  self.widget = MyWidget(fragment_shader_file)
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
    # self.label4.setText(f"(X: {self.widget.width()}, Y: {self.widget.height()})")
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
      self.widget.app_frame = 0
      self.widget.update()
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
  surface_format.setMajorVersion(3)
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


def run_app(fragment_shader_file, offscreen_output_file, w, h, x=2**7, y=2**7):
  setup_misc()
  app = QtWidgets.QApplication.instance() or QtWidgets.QApplication()
  if offscreen_output_file:
    render_offscreen(fragment_shader_file, offscreen_output_file, w, h)
  else:
    window = setup_gui(fragment_shader_file, w, h, x, y)
    setup_interrupt_handler(app)
    app.exec_()


def main():
  import argparse
  parser = argparse.ArgumentParser(description='ShaderApp')
  parser.add_argument('file', type=str, help='glsl fragment shader file (cf. shaders/example0.glsl)')
  parser.add_argument('--width',  type=int, default=2**9 * 5//4, help='resolution width')
  parser.add_argument('--height', type=int, default=2**9,        help='resolution height')
  parser.add_argument('--offscreen', type=str, default=None,     help='offscreen render output file')
  args = parser.parse_args()
  run_app(args.file, args.offscreen, args.width, args.height)


if __name__ == '__main__':
  main()
