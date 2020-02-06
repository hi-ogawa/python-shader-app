#include <cstdio>
#include <cstdint>
#include <cassert>
#include <memory>
#include <map>
#include <vector>

#include <stb_truetype.h>

int main(int argc, char **argv) {
  if (argc != 4) {
    puts("Usage Example: ex00_font_info /usr/share/fonts/TTF/Roboto-Regular.ttf g 16");
    return -1;
  }
  const char* font_file = argv[1];            // e.g. "/usr/share/fonts/TTF/Roboto-Regular.ttf"
  int codepoint = static_cast<int>(*argv[2]); // e.g. 'g'
  int size_px = atoi(argv[3]);                // e.g. 16

  // Initialize font data
  std::vector<uint8_t> buffer; buffer.resize(1<<24);
  stbtt_fontinfo font;
  {
    FILE* fp = fopen(font_file, "rb");
    assert(fp);
    std::unique_ptr<FILE, decltype(&fclose)> raii_action{fp, &fclose};

    fread(buffer.data(), sizeof(buffer[0]), buffer.size(), fp);
    assert(!ferror(fp) && feof(fp));

    int font_offset = stbtt_GetFontOffsetForIndex(buffer.data(), 0);
    assert(font_offset >= 0);
    assert(stbtt_InitFont(&font, buffer.data(), font_offset));
  }

  // Obtain glyph index of codepoint
  int glyph_index = stbtt_FindGlyphIndex(&font, codepoint);
  assert(glyph_index != 0);
  printf("== Codepoint info ==\n");
  printf("codepoint: '%c'\n", codepoint);
  printf("glyph_index: %d\n", glyph_index);
  puts("");

  // Obtain font metric
  {
    // global metric
    {
      std::vector<const char*> names = {
        "ascent",
        "descent",
        "line_gap",
        "x_min",
        "y_min",
        "x_max",
        "y_max",
      };
      std::vector<int> values;
      {
        values.resize(names.size());
        auto& v = values;
        stbtt_GetFontVMetrics(&font, &v[0], &v[1], &v[2]);
        stbtt_GetFontBoundingBox(&font, &v[3], &v[4], &v[5], &v[6]);
      }
      printf("== Global metric ==\n");
      for (size_t i = 0; i < values.size(); i++) {
        printf("%s: %d\n", names[i], values[i]);
      }
      puts("");
    }

    // glyph metric
    {
      std::vector<const char*> names = {
        "advance",
        "bearing",
        "x_min",
        "y_min",
        "x_max",
        "y_max",
      };
      std::vector<int> values;
      {
        values.resize(names.size());
        auto& v = values;
        stbtt_GetCodepointHMetrics(&font, codepoint, &v[0], &v[1]);
        stbtt_GetCodepointBox(&font, codepoint, &v[2], &v[3], &v[4], &v[5]);
      }
      printf("== Font metric of '%c' ==\n", codepoint);
      for (size_t i = 0; i < values.size(); i++) {
        printf("%s: %d\n", names[i], values[i]);
      }
      puts("");
    }
  }

  // Obtain glyph geometry
  {
    stbtt_vertex* vertices;
    int num_vertices = stbtt_GetGlyphShape(
        &font, glyph_index, &vertices);
    assert(num_vertices > 0);
    std::unique_ptr<stbtt_vertex, decltype(&free)> raii_action{vertices, &free};

    printf("== Glyph geometry of '%c' ==\n", codepoint);
    printf("num_vertices: %d\n", num_vertices);
    printf("vertices:\n");
    std::map<uint8_t, const char*> vertex_type_to_cstring = {
      {STBTT_vmove,  "move" },
      {STBTT_vline,  "line" },
      {STBTT_vcurve, "curve"},
      {STBTT_vcubic, "cubic"},
    };
    for (int i = 0; i < num_vertices; i++) {
      stbtt_vertex& v = vertices[i];
      printf("  - type: %s\n", vertex_type_to_cstring[v.type]);
      printf("    padding: %d\n", v.padding);
      printf("    data: [% 5d, % 5d, % 5d, % 5d, % 5d, % 5d]\n",
             v.x, v.y, v.cx, v.cy, v.cx1, v.cy1);
    }
    puts("");
  }

  // Render to ascii
  printf("== Rendering '%c' ==\n", codepoint);
  {
    uint8_t* bitmap;
    int w, h;
    float scale_y = stbtt_ScaleForPixelHeight(&font, size_px);
    bitmap = stbtt_GetGlyphBitmap(&font, 0, scale_y, glyph_index, &w, &h, 0, 0);
    assert(bitmap);
    std::unique_ptr<uint8_t, decltype(&free)> raii_action{bitmap, &free};

    for (int j = 0; j < h; ++j) {
      for (int i = 0; i < w; ++i) {
        putchar(" .:ioVM@"[bitmap[j*w+i]>>5]);
      }
      putchar('\n');
    }
  }
  return 0;
}
