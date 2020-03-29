#
# Miscellaneous helper
#
import sys, traceback, signal
from PySide2 import QtCore


# Wrap buggy function which is constantly invoked from Qt's eventloop
def exit_app_on_exception(func):
    def decorated_func(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except:
            exc_type, message, trace = sys.exc_info()
            print("### exit_app_on_exception ###")
            traceback.print_exc()
            print("#############################")
            sys.exit(QtCore.QCoreApplication.instance().exit(-1))
    return decorated_func


# Let CPython to notice signal by registering timer with empty lambda
def setup_interrupt_handler(app):
  timer = QtCore.QTimer()
  timer.start(500)
  timer.timeout.connect(lambda *_: None)
  signal.signal(signal.SIGINT, lambda *_: app.quit())


# Truncate Qt's builtin debug message (especially for shader compile error)
# Cf. https://doc.qt.io/qt-5/debug.html#warning-and-debugging-messages
def setup_qt_message_handler(truncate_multiline=True):
  def message_handler(message_type, context, message):
      s1 = str(message_type)[len('PySide2.QtCore.QtMsgType.'):]
      if truncate_multiline:
        lines = message.splitlines()
        s2 = lines[0]
        if len(lines) > 1:
          s2 += ' <<multiline truncated>>'
      else:
        s2 = message
      print(f"[{s1}] {s2}")
  QtCore.qInstallMessageHandler(message_handler)


def handle_OpenGL_debug_message(m):
  BLACKLIST = [
    # NOTE: Intel's driver emits this when read/write same framebuffer (e.g. in multipass shader)
    lambda s: s.strip() == "Disabling CCS because a renderbuffer is also bound for sampling.",
  ]
  message = m.message()
  for match_func in BLACKLIST:
    if match_func(message):
      return
  print(f"[QOpenGLDebugLogger] {message}")


# file : str -> (result : str, include_files : [str])
def preprocess_include(file, add_line_directive=True):
  import os, re
  file_dir = os.path.dirname(file)
  with open(file) as f:
    file_content = f.read()
  include_files = [] # [str]
  result = ''
  if add_line_directive:
    result += '#line 1\n'
  for i, line in enumerate(file_content.splitlines(keepends=True)):
    m = re.match('#include "(.*)"', line)
    if m:
      dep = os.path.join(file_dir, m.group(1))
      dep_result, dep_include_files = preprocess_include(dep)
      include_files += ([dep] + dep_include_files)
      result += dep_result
      if add_line_directive:
        result += f"#line {i + 2}\n"
    else:
      result += line
  return result, include_files


class PreprocessIncludeWatcher(QtCore.QObject):
  changed = QtCore.Signal()

  # in_file : str
  def __init__(self, in_file):
    super(PreprocessIncludeWatcher, self).__init__()
    self.in_file = in_file
    self.qt_watcher = QtCore.QFileSystemWatcher([in_file])
    self.qt_watcher.fileChanged.connect(self.handle_changed)
    self.update(emit_signal=False)

  # Ignore empty file which can be sometimes produced by file writer transitionally
  def handle_changed(self, path):
    with open(path) as f:
      src = f.read()
    if len(src) == 0:
      print(f"[PreprocessIncludeWatcher] ignore empty file {path}")
    else:
      self.update(emit_signal=True)

  # emit_signal : bool
  def update(self, emit_signal):
    _, include_files = preprocess_include(self.in_file)
    self.qt_watcher.removePaths(self.qt_watcher.files())
    self.qt_watcher.addPaths([self.in_file] + include_files)
    if emit_signal:
      self.changed.emit()
    print(f"[PreprocessIncludeWatcher] watching ( {', '.join(self.qt_watcher.files())} )")


# src : str -> config : dict
def parse_shader_config(src):
  """
  Shader configuration example:

    %%config-start%%
    samplers:
      - name: buffer0
        type: framebuffer
      - name: buffer1
        type: framebuffer

    programs:
      - name: mainImage1
        output: $default
        samplers:
          - buffer0
          - buffer1

      - name: mainImage2
        output: buffer0
        samplers:
          - buffer0

      - name: mainImage3:
        output: buffer1
        samplers:
          - buffer1

    offscreen_option:
      fps: 60
      num_frames: 300
    %%config-end%%

  NOTE:
    - Such configuration will generate source code e.g.

        layout (location = 0) out vec4 iMainFragColor;
        uniform sampler2D iSampler0;
        uniform sampler2D iSampler1;
        void main() {
          mainImage1(iMainFragColor, vec2(gl_FragCoord), iSampler0, iSampler1);
        }

      So, this expects mainImage1's signiture to be:

        void mainImage1(out vec4, vec2, Sampler2D, Sampler2D);

    - Order of execution is order of "programs".

    - "samplers" and "offscreen_option" continue to change. (cf. ex20, ex29)
  """
  import re, yaml
  start = re.search('%%config-start%%', src)
  end = re.search('%%config-end%%', src)
  if not (start and end):
    return None

  config = yaml.load(src[start.end():end.start()], Loader=yaml.SafeLoader)
  return config


# cf. https://stackoverflow.com/questions/15506971/recursive-version-of-reload
def reload_rec(root):
  from importlib import reload
  from types import ModuleType
  import os

  root = reload(root)
  root_dir = os.path.dirname(root.__file__)
  visited = set()
  stack = [root]
  while len(stack) > 0:
    m = stack.pop()
    visited.add(m)
    for key in dir(m):
        c = getattr(m, key)
        go = type(c) is ModuleType and \
             not (c in visited) and \
             os.path.dirname(c.__file__).startswith(root_dir)
        if go:
          reload(c)
          stack.append(c)
  return root
