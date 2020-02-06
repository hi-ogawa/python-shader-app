#
# stbtt wrapper based on what I've tried in ex00_font_info.py
#

import ctypes
from ctypes import c_int, c_float, c_void_p, c_short, c_char, byref, string_at

stb = None
def load_library(filename):
  global stb

  # dlopen (LD)
  stb = ctypes.cdll.LoadLibrary(filename)

  # Define non-int function return value
  stb.stbtt_ext_AllocFontinfo.restype = c_void_p
  stb.stbtt_ScaleForPixelHeight.restype = c_float
  stb.stbtt_GetGlyphBitmap.restype = c_void_p


class StbttVertex(ctypes.Structure):
  _fields_ = \
    [(name, c_short) for name in ['x', 'y', 'cx', 'cy', 'cx1', 'cy1']] + \
    [(name, c_char ) for name in ['type', 'padding']]

  type_to_str = ["NA", "move", "line", "curve", "cubic"]

  def to_dict(self):
    ls = \
      [ ('type', StbttVertex.type_to_str[self.type[0]]), ('padding', self.padding[0]) ] + \
      [ (k, getattr(self, k)) for k in ['x', 'y', 'cx', 'cy', 'cx1', 'cy1']]
    return dict(ls)


class StbttContext():
  def __init__(self):
    if stb is None:
      raise RuntimeError("First call load_libstb to load dynamic library")
    self.font = c_void_p(stb.stbtt_ext_AllocFontinfo())
    self.fontdata = None

  def __delete__(self):
    stb.stbtt_ext_FreeFontinfo(self.font)

  def load_font(self, fontfile, font_index=0):
    with open(fontfile, 'rb') as f:
      self.fontdata = f.read()
    font_offset = stb.stbtt_GetFontOffsetForIndex(self.fontdata, font_index)
    assert font_offset >= 0
    status = stb.stbtt_InitFont(self.font, self.fontdata, font_offset)
    assert status != 0

  def get_global_metrics(self):
    metrics = dict((name, c_int()) for name in [
        'ascent', 'descent', 'line_gap', 'x_min', 'y_min', 'x_max', 'y_max'])
    stb.stbtt_GetFontVMetrics(
        self.font, *[byref(metrics[k]) for k in ['ascent', 'descent', 'line_gap']])
    stb.stbtt_GetFontBoundingBox(
        self.font, *[byref(metrics[k]) for k in ['x_min', 'y_min', 'x_max', 'y_max']])
    return dict((k, v.value) for k, v in metrics.items())

  # codepoint: unicode one character string
  def get_glyph_index(self, codepoint):
    glyph_index = stb.stbtt_FindGlyphIndex(self.font, ord(codepoint));
    if glyph_index == 0:
      raise RuntimeError("Glyph not found")
    return glyph_index

  def get_glyph_metrics(self, glyph_index):
    metrics = dict((name, c_int()) for name in [
        'advance', 'bearing', 'x_min', 'y_min', 'x_max', 'y_max'])
    stb.stbtt_GetGlyphHMetrics(
        self.font, glyph_index, *[byref(metrics[k]) for k in ['advance', 'bearing']]);
    stb.stbtt_GetGlyphBox(
        self.font, glyph_index, *[byref(metrics[k]) for k in ['x_min', 'y_min', 'x_max', 'y_max']]);
    return dict((k, v.value) for k, v in metrics.items())

  def get_glyph_shape(self, glyph_index, copy=True): # -> vertices
    ptr_vertices = c_void_p(0)
    num_vertices = stb.stbtt_GetGlyphShape(self.font, glyph_index, byref(ptr_vertices))
    assert ptr_vertices.value > 0

    ArrayType = StbttVertex * num_vertices
    vertices = ArrayType.from_address(ptr_vertices.value)
    if copy:
      vertices = ArrayType.from_buffer_copy(vertices)
      stb.stbtt_FreeShape(self.font, ptr_vertices)
    return vertices
