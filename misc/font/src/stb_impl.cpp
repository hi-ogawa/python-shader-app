#define STB_TRUETYPE_IMPLEMENTATION
#include <stb_truetype.h>

//
// Create malloc/free routine so that python ctypes can interface it easily
//

#ifdef __cplusplus
extern "C" {
#endif

STBTT_DEF stbtt_fontinfo* stbtt_ext_AllocFontinfo() {
  return new stbtt_fontinfo;
}

STBTT_DEF void stbtt_ext_FreeFontinfo(stbtt_fontinfo* fontinfo) {
  delete fontinfo;
}

#ifdef __cplusplus
} // extern "C"
#endif
