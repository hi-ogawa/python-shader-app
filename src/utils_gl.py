from PySide2 import QtGui, QtCore
import OpenGL.GL as gl
import numpy as np
from .utils import if3


def setup_texture_data(target, filename, config):
  if filename.endswith('.hdr'):
    setup_texture_data_hdr(target, filename, config)
  else:
    setup_texture_data_qimage(target, filename, config)


def setup_texture_data_qimage(target, filename, config):
  qimage = QtGui.QImage(filename)
  qimage_format = qimage.format()
  assert qimage_format != QtGui.QImage.Format_Invalid

  if config.get('y_flip'):
    qimage = qimage.mirrored(False, True)

  if qimage_format != QtGui.QImage.Format_RGBA8888:
    qimage = qimage.convertToFormat(QtGui.QImage.Format_RGBA8888)

  W, H = qimage.width(), qimage.height()
  data = qimage.constBits()
  gl.glTexImage2D(target, 0, gl.GL_RGBA8, W, H, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, data)


def setup_texture_data_hdr(target, filename, config):
  import misc.hdr.src.main_v2 as hdr
  data = hdr.load_file(filename)
  if config.get('y_flip'):
    data = np.flip(data, axis=0)

  H, W = data.shape[:2]
  gl.glTexImage2D(target, 0, gl.GL_RGB32F, W, H, 0, gl.GL_RGB, gl.GL_FLOAT, data)


def setup_texture_parameters(target, config):
  gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_S, if3(config.get('wrap') == 'repeat', gl.GL_REPEAT, gl.GL_CLAMP_TO_EDGE))
  gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_T, if3(config.get('wrap') == 'repeat', gl.GL_REPEAT, gl.GL_CLAMP_TO_EDGE))
  gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_R, if3(config.get('wrap') == 'repeat', gl.GL_REPEAT, gl.GL_CLAMP_TO_EDGE))
  gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER, if3(config.get('filter') == 'linear', gl.GL_LINEAR, gl.GL_NEAREST))
  gl.glTexParameteri(target, gl.GL_TEXTURE_MAG_FILTER, if3(config.get('filter') == 'linear', gl.GL_LINEAR, gl.GL_NEAREST))
  if config.get('mipmap'):
    gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER, if3(config.get('filter') == 'linear', gl.GL_LINEAR_MIPMAP_LINEAR, gl.GL_NEAREST))
    gl.glTexParameteri(target, gl.GL_TEXTURE_BASE_LEVEL, 0)
    gl.glTexParameteri(target, gl.GL_TEXTURE_MAX_LEVEL, 10)
    gl.glGenerateMipmap(target)
