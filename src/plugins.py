import OpenGL.GL as gl
from array import array  # used from "eval(data)" in SsboPlugin


class Plugin():
  def configure(self): pass
  def cleanup(self): pass
  def on_begin_draw(self): pass
  def on_draw(self): pass
  def on_end_draw(self): pass


class SsboPlugin(Plugin):
  def configure(self, config):
    self.config = config
    self.binding = self.config['binding']
    self.ssbo = gl.glGenBuffers(1)
    data = self.get_data()
    if data:
      gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, self.ssbo)
      gl.glBufferData(gl.GL_SHADER_STORAGE_BUFFER, len(data), self.get_data(), gl.GL_DYNAMIC_DRAW);
      gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, 0);

  def get_data(self): # -> bytes
    _type = self.config['type']
    data  = self.config['data']
    if _type == 'inline':
      return eval(data).tobytes()
    if _type == 'file':
      return open(data, 'rb').read()
    return None

  def cleanup(self):
    gl.glDeleteBuffers(1, self.ssbo)

  def on_begin_draw(self):
    gl.glBindBufferBase(gl.GL_SHADER_STORAGE_BUFFER, self.binding, self.ssbo);

  def on_end_draw(self):
    gl.glBindBuffer(gl.GL_SHADER_STORAGE_BUFFER, 0);
