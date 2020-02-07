import ctypes
from ctypes import c_int, c_float, c_void_p, c_short, c_char, byref, string_at

# dlopen
stb = ctypes.cdll.LoadLibrary("./build/libstb.so")

# Define non-int function return value
stb.stbtt_ext_AllocFontinfo.restype = c_void_p
stb.stbtt_ScaleForPixelHeight.restype = c_float
stb.stbtt_GetGlyphBitmap.restype = c_void_p # raw memory bytes can be accessed via ctypes.string_at

# Define wrapper for automatic malloc/free
class Fontinfo:
  def __init__(self):
    self.ptr_fontinfo = stb.stbtt_ext_AllocFontinfo()
    self._as_parameter_ = c_void_p(self.ptr_fontinfo)

  def __delete__(self):
    stb.stbtt_ext_FreeFontinfo(self.ptr_fontinfo)


#
# Reimplementation of  ex00_font_info.cpp
#

fontfile = "/usr/share/fonts/TTF/Roboto-Regular.ttf"
codepoint = b"J"
size_px = 16

#
# Initialization
#
font = Fontinfo()
with open(fontfile, 'rb') as f:
  fontdata = f.read()

font_offset = stb.stbtt_GetFontOffsetForIndex(fontdata, 0)
assert font_offset >= 0

status = stb.stbtt_InitFont(font, fontdata, font_offset)
assert status != 0

glyph_index = stb.stbtt_FindGlyphIndex(font, ord(codepoint));
assert glyph_index != 0

print("== Codepoint info ==")
print(dict(codepoint=codepoint, glyph_index=glyph_index))
print("")


#
# Obtain metrics
#
global_metrics = dict((name, c_int()) for name in [
    'ascent', 'descent', 'line_gap', 'x_min', 'y_min', 'x_max', 'y_max'])
stb.stbtt_GetFontVMetrics(
    font, *[byref(global_metrics[k]) for k in ['ascent', 'descent', 'line_gap']]);
stb.stbtt_GetFontBoundingBox(
    font, *[byref(global_metrics[k]) for k in ['x_min', 'y_min', 'x_max', 'y_max']]);

glyph_metrics = dict((name, c_int()) for name in [
    'advance', 'bearing', 'x_min', 'y_min', 'x_max', 'y_max'])
stb.stbtt_GetGlyphHMetrics(
    font, glyph_index, *[byref(glyph_metrics[k]) for k in ['advance', 'bearing']]);
stb.stbtt_GetGlyphBox(
    font, glyph_index, *[byref(glyph_metrics[k]) for k in ['x_min', 'y_min', 'x_max', 'y_max']]);

print("== Global metrics ==")
print(dict((k, v.value) for k, v in global_metrics.items()))
print("")

print("== Glyph metrics ==")
print(dict((k, v.value) for k, v in glyph_metrics.items()))
print("")

#
# Obtain glyph geometry
#
ptr_vertices = c_void_p(0)
num_vertices = stb.stbtt_GetGlyphShape(font, glyph_index, byref(ptr_vertices));
assert num_vertices > 0

# Define stbtt_vertex's byte alignment in ctypes
# TODO: somehow we get "uninitialized-value" looking data for `padding`, `cx1`, `cy1`.
class Vertex(ctypes.Structure):
  _fields_ = \
    [(name, c_short) for name in ['x', 'y', 'cx', 'cy', 'cx1', 'cy1']] + \
    [(name, c_char ) for name in ['type', 'padding']]

  type_to_str = ["NA", "move", "line", "curve", "cubic"]

  def to_dict(self):
    result = {}
    result['type'] = Vertex.type_to_str[self.type[0]]
    result['padding'] = self.padding[0]
    for name in ['x', 'y', 'cx', 'cy', 'cx1', 'cy1']:
      result[name] = getattr(self, name)
    return result

# Magical array instantiation
vertices = (Vertex * num_vertices).from_address(ptr_vertices.value)

print("== Glyph geomerty ==")
for vertex in vertices:
  print(vertex.to_dict())
print("")

stb.stbtt_FreeShape(font, ptr_vertices)


#
# Rasterize to bitmap
#
scale_y = stb.stbtt_ScaleForPixelHeight(font, c_float(size_px))
w, h = c_int(), c_int()
ptr_bitmap = stb.stbtt_GetGlyphBitmap(
    font, c_float(0), c_float(scale_y),
    glyph_index, byref(w), byref(h), byref(c_int(0)), byref(c_int(0)))
bitmap = string_at(ptr_bitmap, size=w.value * h.value)

print("== Rendering ==")
for i in range(h.value):
  for j in range(w.value):
    idx = i * w.value + j
    print(" .:ioVM@"[bitmap[idx] >> 5], end='')
  print()

stb.stbtt_FreeBitmap(c_void_p(ptr_bitmap), 0)
