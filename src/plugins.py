import OpenGL.GL as gl
import ctypes


class Plugin():
  def configure(self, config, W, H): pass
  def cleanup(self): pass
  def on_begin_draw(self): pass
  def on_draw(self): pass
  def on_end_draw(self): pass


class SsboPlugin(Plugin):
  def configure(self, config, W, H):
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
      return bs, len(bs)

    raise RuntimeError(f"[SsboPlugin] Invalid type : {typ}")

  def cleanup(self):
    gl.glDeleteBuffers(1, self.ssbo)

  def on_begin_draw(self):
    gl.glBindBufferBase(gl.GL_SHADER_STORAGE_BUFFER, self.binding, self.ssbo);

  def on_end_draw(self):
    gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, 0);
