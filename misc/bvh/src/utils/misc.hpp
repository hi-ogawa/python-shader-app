#pragma once

#include <array>
#include <optional>
#include <algorithm>

#include "common.hpp"
#include "format.hpp"
#include "geometry.hpp"


namespace utils {

using std::string, std::vector, std::array;

//
// 2 dim contiguous buffer
//
template<typename T>
struct vector2 {
  static_assert(!std::is_same_v<T, bool>, "`bool` is not supported. Use `char` instead.");

  vector<T> v;
  size_t num_rows, num_cols;

  void resize(size_t in_num_rows, size_t in_num_cols) {
    num_rows = in_num_rows;
    num_cols = in_num_cols;
    v.resize(num_rows * num_cols);
  }

  T& operator()(size_t row, size_t col) {
    return v.data()[num_cols * row + col];
  }
};

//
// map vector
//
template<typename T1, typename T2, typename TMap>
inline vector<T1> mapVector(const vector<T2>& v, TMap map_func) {
  vector<T1> result;
  result.resize(v.size());
  for (auto i = 0; i < v.size(); i++) {
    result[i] = map_func(v[i]);
  }
  return result;
}

//
// strip string
//
inline void lstrip_(string& s) {
  auto it = std::find_if(s.begin(), s.end(), [](int c){ return !std::isspace(c); });
  s.erase(s.begin(), it);
}
inline void rstrip_(string& s) {
  auto it = std::find_if(s.rbegin(), s.rend(), [](int c){ return !std::isspace(c); });
  s.erase(it.base(), s.end());
}
inline void strip_(string& s) {
  lstrip_(s);
  rstrip_(s);
}
inline string lstrip(const string& s) {
  string result = s;
  lstrip_(result);
  return result;
}
inline string rstrip(const string& s) {
  string result = s;
  rstrip_(result);
  return result;
}
inline string strip(const string& s) {
  string result = s;
  strip_(result);
  return result;
}
inline string join(const vector<string>& ls, const string& sep = " ") {
  string result;
  for (auto i = 0; i < ls.size(); i++) {
    if (i > 0)
      result += sep;
    result += ls[i];
  }
  return result;
}
inline string dirname(const string& s) {
  return string{s, 0, s.rfind('/')};
}
inline string basename(const string& s) {
  auto npos = std::string::npos;
  auto pos = s.rfind("/");
  return pos == npos ? s : s.substr(pos + 1, npos);
}

//
// Quick debug print macro
//
#define ddd(FORMAT, ...) \
  print(string{"[debug:%s:%d] "} + FORMAT + "\n", basename(__FILE__), __LINE__, __VA_ARGS__)


//
// .ppm writer
//
struct PPMWriter {
  int w, h;
  u8vec3* p_data;

  friend std::ostream& operator<<(std::ostream& os, const PPMWriter& self) {
    auto w = self.w, h = self.h;
    auto p_data = self.p_data;
    string header = lstrip(R"(
P3
%d %d
255
)");
    os << format(header, w, h);
    for (auto y = 0; y < h; y++) {
      for (auto x = 0; x < w; x++) {
        os << format("%d %d %d\n", (*p_data)[0], (*p_data)[1], (*p_data)[2]);
        p_data++;
      }
    }
    return os;
  }
};


//
// Command line parser
//
struct Cli {
  const int argc; const char** argv;
  string help_message;

  string help() {
    return format("usage: %s %s\n", argv[0], rstrip(help_message));
  }

  template<typename T>
  T parse(const char* s) {
    std::istringstream stream{s};
    T result;
    stream >> result;
    return result;
  }

  template<>
  string parse(const char* s) {
    return string{s};
  }

  template<typename T>
  std::optional<T> getArg(const string& flag) {
    help_message += format("[%s ?]", flag) + " ";
    for (auto i = 1; i < argc; i++) {
      if (argv[i] == flag && i + 1 < argc) {
        return parse<T>(argv[i + 1]);
      }
    }
    return {};
  }

  bool checkArg(const string& flag) {
    help_message += format("[%s]", flag) + " ";
    for (auto i = 1; i < argc; i++) {
      if (argv[i] == flag) {
        return true;
      }
    }
    return false;
  }
};


} // namespace utils
