#pragma once

#include <cstring>

#include <array>
#include <optional>
#include <algorithm>
#include <map>
#include <variant>
#include <fstream>
#include <memory>

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

inline string slice(const string&s, int begin, int end) {
  int n = s.size();
  if (n == 0) return "";
  return s.substr((begin + n) % n, (end - begin + n) % n);
}

inline int index(const string& s, const string& sub) {
  size_t n = s.size();
  size_t k = sub.size();
  const char* c1 = s.c_str();
  const char* c2 = sub.c_str();
  for (auto i = 0; i + k <= n; i++) {
    if (strncmp(c1, c2, k) == 0)
      return i;
    c1++;
  }
  return -1;
}

inline void split_append(const string& s, const string& sep, /*out*/ vector<string>& appendee) {
  int p = index(s, sep);
  if (p == -1) {
    appendee.push_back(s);
    return;
  }
  size_t k = sep.size();
  appendee.push_back(slice(s, 0, p));
  split_append(slice(s, p + k, 0), sep, appendee);
}

inline vector<string> split(const string& s, const string& sep = " ") {
  vector<string> result;
  split_append(s, sep, result);
  return result;
}

inline string dirname(const string& s) {
  return s.substr(0, s.rfind('/'));
}
inline string basename(const string& s) {
  auto npos = std::string::npos;
  auto pos = s.rfind("/");
  return pos == npos ? s : s.substr(pos + 1, npos);
}

template<typename TValue, typename TContainer = std::initializer_list<TValue>>
inline bool b_find(const TContainer& c, const TValue& v) {
  return std::find(c.begin(), c.end(), v) != c.end();
}

template<typename TContainer, class UnaryPredicate>
inline bool b_find_if(const TContainer& c, UnaryPredicate p) {
  return std::find_if(c.begin(), c.end(), p) != c.end();
}

template<typename T>
inline T sto(const std::string& s);

template<>
inline fvec3 sto(const std::string& s) {
  fvec3 v;
  std::istringstream istr{s};
  istr >> v[0] >> v[1] >> v[2];
  return v;
}

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


//
// Minimal Yaml-like language parser
// - fixed indent for nesting: two spaces
// - data types: null, string, dict, list
//

using std::map, std::variant, std::shared_ptr, std::make_shared;

struct Yeml {
  struct Null {};
  using Dict = map<string, shared_ptr<Yeml>>;
  using List = vector<shared_ptr<Yeml>>;
  variant<Null, Dict, List, string> data;
  inline static Null null;

  Yeml() : data{null} { }
  Yeml(const string& in_data) : data{in_data} { }
  Yeml(const Yeml& other) : data{other.data} { }
  explicit operator bool() { return !isNull(); }

  bool isNull() const { return std::holds_alternative<Null>(data); }
  bool isDict() const { return std::holds_alternative<Dict>(data); }
  bool isList() const { return std::holds_alternative<List>(data); }
  bool isStr()  const { return std::holds_alternative<string>(data); }

  Dict&   asDict() { return std::get<Dict>(data);   }
  List&   asList() { return std::get<List>(data);   }
  string& s()      { return std::get<string>(data); }
  const Dict&   asDict() const { return std::get<Dict>(data);   }
  const List&   asList() const { return std::get<List>(data);   }
  const string& s()      const { return std::get<string>(data); }

  // safe getter
  std::optional<shared_ptr<Yeml>> d(const string& key) {
    if (!isDict()) return {};
    if (!b_find_if(asDict(), [&key](auto kv) { return kv.first == key; }))
      return {};
    return asDict()[key];
  }
  std::optional<shared_ptr<Yeml>> d(size_t i) {
    if (!isList()) return {};
    if (!(i < asList().size())) return {};
    return asList()[i];
  }
  // safe getter (directly string value)
  std::optional<string> ds(const string& key) {
    if (!isDict()) return {};
    if (!b_find_if(asDict(), [&key](auto kv) { return kv.first == key; })) return {};
    if (!asDict()[key]->isStr()) return {};
    return asDict()[key]->s();
  }
  std::optional<string> ds(size_t i) {
    if (!isList()) return {};
    if (!(i < asList().size())) return {};
    if (!asList()[i]->isStr()) return {};
    return asList()[i]->s();
  }

  // unsafe getter
  Yeml& operator[](const string& key) {
    auto opt = d(key);
    if (!opt)
      throw std::runtime_error{format("KeyError: %s", key)};
    return **opt;
  }
  Yeml& operator[](const size_t i) {
    auto opt = d(i);
    if (!opt)
      throw std::runtime_error{format("IndexError: %d", i)};
    return **opt;
  }
  // unsafe getter (directly string reference)
  string& operator()(const string& key) {
    Yeml& y = (*this)[key];
    if (!y.isStr())
      throw std::runtime_error{format("TypeError: key [\"%s\"] not string", key)};
    return y.s();
  }
  string& operator()(const size_t i) {
    Yeml& y = (*this)[i];
    if (!y.isStr())
      throw std::runtime_error{format("TypeError: index [%d] not string", i)};
    return y.s();
  }


  //
  // Parser implementation
  //
  struct Detail {
    //
    // Some utilities
    //
    static void separateIndent(const string& line, /*out*/ int& indent, string& dedent_line) {
      dedent_line = lstrip(line);
      indent = line.size() - dedent_line.size();
    }

    static string preprocessLine(const string& line) {
      string result = line;

      // Strip line comment
      int pos = index(line, "#");
      if (pos >= 0) result = slice(result, pos, 0);

      // Strip trailing spaces
      result = rstrip(result);

      return result;
    }

    static std::istream& peekLine(std::istream& istr, /*out*/ string& line) {
      int pos = istr.tellg();
      std::getline(istr, line);
      istr.seekg(pos, std::ios_base::beg);
      return istr;
    }

    static std::istream& peekLinePreprocessed(std::istream& istr, /*out*/ string& line) {
      while (true) {
        if (!peekLine(istr, line)) { break; }
        preprocessLine(line);
        if (line.size() > 0) { break; } // return if non empty
        std::getline(istr, line);       // otherwise consume and repeat
      }
      return istr;
    }


    // There are only 7 exclusive line patterns
    // (0) xyz
    // (1) xyz:
    // (2) xyz: abc
    // (3) -
    // (4) - xyz
    // (5) - xyz:
    // (6) - xyz: abc
    static void parseLine(const string& line, /*out*/ int& pattern, string& value1, string& value2) {
      vector<string> splits = split(line, ": ");
      bool a = slice(line, -1, 0) == ":";
      bool b = splits.size() == 2;
      bool c = slice(line, 0, 2) == "- ";
      bool d = line == "-";
      pattern =
        d ? 3 : (
          c ? (
            a ? 5 :
            b ? 6 :
                4
          ) : (
            a ? 1 :
            b ? 2 :
                0
          )
        );
      if (pattern == 0) { value1 = line; }
      if (pattern == 1) { value1 = slice(line, 0, -1); }
      if (pattern == 2) { value1 = splits[0]; value2 = splits[1]; }
      if (pattern == 3) {}
      if (pattern == 4) { value1 = slice(line, 2,  0); }
      if (pattern == 5) { value1 = slice(line, 2, -1); }
      if (pattern == 6) { value1 = slice(splits[0], 2, 0); value2 = splits[1]; }
    }

    static void recParse(std::istream& istr, int indent, /*out*/ Yeml& result, bool debug = false) {
      // Done if nothing is left in stream after skipping empty line and comments
      string line;
      if (!peekLinePreprocessed(istr, line)) return;

      // Done if current indent is shallow
      int cur_indent;
      string ded_line;
      separateIndent(line, cur_indent, ded_line);
      if (cur_indent < indent) return;

      // Consume line and find pattern
      std::getline(istr, line);
      int pattern;
      string value1, value2;
      parseLine(ded_line, pattern, value1, value2);

      if (debug) {
        ddd("parseLine => [%d][%s][%s]", pattern, value1, value2);
      }

      // Assert some conditions
      string error_message = format(R"(SyntaxError: unexpected line "%s")", line);
      if (b_find({0}, pattern)) {
        if (!result.isNull())
          throw std::runtime_error{error_message};
      }
      if (b_find({1, 2}, pattern)) {
        if (!(result.isNull() || result.isDict()))
          throw std::runtime_error{error_message};
        if (result.isNull()) {
          result.data = Dict{};
        }
      }
      if (b_find({3, 4, 5, 6}, pattern)) {
        if (!(result.isNull() || result.isList()))
          throw std::runtime_error{error_message};
        if (result.isNull()) {
          result.data = List{};
        }
      }

      // Update `result` based on pattern
      // - pattern 0:                 direct return
      // - pattern 1, 3, 5, 6:        non-tail recurse
      // - pattern 1, 2, 3, 4, 5, 6:  tail recurse

      // (0) xyz
      if (pattern == 0) {
        result.data = value1;
        return;
      }

      // (1) xyz:
      if (pattern == 1) {
        auto inner_result = make_shared<Yeml>();
        recParse(istr, indent + 2, *inner_result, debug);

        std::get<Dict>(result.data)[value1] = inner_result;
      }

      // (2) xyz: abc
      if (pattern == 2) {
        std::get<Dict>(result.data)[value1] = make_shared<Yeml>(value2);
      }

      // (3) -
      if (pattern == 3) {
        auto inner_result = make_shared<Yeml>();
        recParse(istr, indent + 2, *inner_result, debug);

        std::get<List>(result.data).push_back(inner_result);
      }

      // (4) - xyz
      if (pattern == 4) {
        std::get<List>(result.data).push_back(make_shared<Yeml>(value1));
      }

      // (5) - xyz:
      if (pattern == 5) {
        auto inner4_result = make_shared<Yeml>();
        recParse(istr, indent + 4, *inner4_result, debug);

        auto inner2_result = make_shared<Yeml>();
        inner2_result->data = Dict{{value1, inner4_result}};
        recParse(istr, indent + 2, *inner2_result, debug);

        std::get<List>(result.data).push_back(inner2_result);
      }

      // (6) - xyz: abc
      if (pattern == 6) {
        auto inner_result = make_shared<Yeml>();
        inner_result->data = Dict{{value1, make_shared<Yeml>(value2)}};
        recParse(istr, indent + 2, *inner_result, debug);

        std::get<List>(result.data).push_back(inner_result);
      }

      // Parse further lines at same indent (by tail recursion)
      recParse(istr, indent, result, debug);
    }
  };

  friend inline std::istream& operator>>(std::istream& istr, Yeml& result) {
    result.data = null;
    Detail::recParse(istr, /*indent*/ 0, result);
    return istr;
  }

  static Yeml parse(std::istream& istr, bool debug = false) {
    Yeml result;
    Detail::recParse(istr, /*indent*/ 0, result, debug);
    if (istr)
      throw std::runtime_error{"SyntaxError: not all input consumed"};
    return result;
  }

  static Yeml parse(const string& str, bool debug = false) {
    std::istringstream istr{str};
    return parse(istr, debug);
  }

  static Yeml parseFile(const string& filename, bool debug = false) {
    std::ifstream istr{filename};
    MY_ASSERT(istr.is_open());
    return parse(istr, debug);
  }

  void dump(std::ostream& ostr, int indent) const {
    string indent_str(indent, ' ');
    if (isStr()) {
      ostr << format("%s%s\n", indent_str, s());
    } else
    if (isDict()) {
      for (auto& [key, value] : asDict()) {
        if (value->isStr()) {
          ostr << format("%s%s: %s\n", indent_str, key, value->s());
        } else {
          ostr << format("%s%s:\n", indent_str, key);
          (*value).dump(ostr, indent + 2);
        }
      }
    } else
    if (isList()) {
      for (auto& value : asList()) {
        if (value->isStr()) {
          ostr << format("%s- %s\n", indent_str, value->s());
        } else {
          ostr << format("%s-\n", indent_str);
          (*value).dump(ostr, indent + 2);
        }
      }
    }
  }

  friend std::ostream& operator<<(std::ostream& ostr, const Yeml& self) {
    self.dump(ostr, /*indent*/ 0);
    return ostr;
  }
};


//
// Global class registry
//

struct ClassRegistry {
  using new_func_t = std::function<void*(Yeml&)>;
  inline static map<string, new_func_t> data;
};
#define REGISTER_CLASS(CLASS)                                      \
  struct CLASS ## __Registerer {                                   \
    CLASS ## __Registerer () {                                     \
      ClassRegistry::data[#CLASS] = [](Yeml& y){ return new CLASS{y}; };  \
    }                                                              \
  } CLASS ## __Registerer__instance;                               \


//
// PCG pseudo random generator (https://github.com/imneme/pcg-c-basic)
//

struct Rng {
  uint64_t state, inc;
  Rng() : Rng(0x1234, 0x5678) {}
  Rng(uint64_t init_state, uint64_t init_seq) { seed(init_state, init_seq); }

  void seed(uint64_t init_state, uint64_t init_seq) {
    state = 0u;
    inc = (init_seq << 1u) | 1u;
    next();
    state += init_state;
    next();
  }

  uint32_t next() {
    uint64_t oldstate = state;
    state = oldstate * 6364136223846793005ULL + inc;
    uint32_t xorshifted = ((oldstate >> 18u) ^ oldstate) >> 27u;
    uint32_t rot = oldstate >> 59u;
    return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
  }

  float uniform() {
    uint32_t x = next();

    // Use lower 23 bits to make [0, 1) by
    //   2^{127 - 127} * 1.x[22..0] - 1.0
    uint32_t y = (127u << 23u) | (0x7fffffu & x);
    return *reinterpret_cast<float*>(&y) - 1.0;
  }

  fvec2 uniform2() {
    return fvec2{uniform(), uniform()};
  }
};


//
// Various transformation
//

fvec3 map_Spherical_Cartesian(fvec3 rtp) {
  using glm::cos, glm::sin;
  return fvec3{
    rtp[0] * sin(rtp[1]) * cos(rtp[2]),
    rtp[0] * sin(rtp[1]) * sin(rtp[2]),
    rtp[0] * cos(rtp[1]),
  };
}

fvec2 map_Polar_Cartesian(fvec2 rp) {
  using glm::cos, glm::sin;
  return fvec2{
    rp[0] * cos(rp[1]),
    rp[0] * sin(rp[1]),
  };
}

// (Almost everywhere) constant Jacobian 2d-isotopy between square and disk by Shirly and Chiu
fvec2 map_Square_Disk_radius_phi(fvec2 u) {
  using glm::sign, glm::abs;

  // [0, 1]^2 -> [-1, 1]^2
  u = 2.0f * u - 1.0f;

  // Flip around to the 1/8 part of square { (x, y) | x in [0, 1], y in [0, x] }
  fvec2 sign_u = sign(u);
  fvec2 abs_u = abs(u);
  bool swap_xy = abs_u[0] < abs_u[1];
  fvec2 eighth_u = !swap_xy ? abs_u : fvec2{abs_u[1], abs_u[0]};

  float radius = eighth_u[0];
  float phi = M_PI / 4.0 * eighth_u[1] / eighth_u[0]; // in [0, pi/4]

  // Flip back to the original part
  phi = !swap_xy ? phi : (M_PI / 4.0 - phi);        // in [0, pi/2]
  phi = 0 < sign_u[0] ? phi : (M_PI - phi);         // in [0, pi]
  phi = 0 < sign_u[1] ? phi : (2.0 * M_PI - phi);   // in [0, 2pi]

  return fvec2{radius, phi};
}

fvec2 map_Square_Disk(fvec2 u) {
  return map_Polar_Cartesian(map_Square_Disk_radius_phi(u));
}


//
// Sampling routines
//

void sample_HemisphereCosine(fvec2 u, /*out*/ fvec3& p, float& pdf) {
  using glm::acos, glm::cos;

  //
  // [ "Straight-forward" version ]
  //
  {
    float phi   = 2.0f * M_PI * u[0];
    float theta = 0.5f * acos(1.0f - 2.0f * u[1]);
    p = map_Spherical_Cartesian(fvec3{1, theta, phi});
    pdf = cos(theta) / M_PI;
    return;
  }

  //
  // [ 2d Square isotopy version ]
  //
  // Map to uniform on disk (but its polar coord [0, 1] x [0, 2pi] not uniform)
  fvec2 rp = map_Square_Disk_radius_phi(u);
  float radius = rp[0]; // P(r) = 2r (F(r) = r^2)
  float phi = rp[1];    // P(phi) : uniform

  // Map to uniform on [0, 1]
  float u1 = radius * radius;

  // Map to P(theta) \propto cos(t)sin(t)
  float theta = 0.5f * acos(1.0f - 2.0f * u1);

  p = map_Spherical_Cartesian(fvec3{1, theta, phi});
  pdf = cos(theta) / M_PI;
}


} // namespace utils
