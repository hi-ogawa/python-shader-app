#
# Usage example of stbtt wrapper
#

from . import stbtt

def main(fontfile, codepoint):
  ctx = stbtt.StbttContext()
  ctx.load_font(fontfile)
  print(ctx.get_global_metrics())

  glyph_index = ctx.get_glyph_index(codepoint)
  print(glyph_index)
  print(ctx.get_glyph_metrics(glyph_index))

  vertices = ctx.get_glyph_shape(glyph_index)
  for vertex in vertices:
    print(vertex.to_dict())
