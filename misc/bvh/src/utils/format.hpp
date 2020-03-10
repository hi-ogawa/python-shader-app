#pragma once

#include <cstdio>

#include "common.hpp"


namespace utils {

//
// Trivial extension of "printf" supporting any streamable object for "%s".
// (e.g. format("xxx %s", some_object) where (cout << some_object) is defined.)
//

// TODO:
// it seems char literal causes "ambiguous template" as it matches either
// - const char* => is_scalar
// - char[N]     => not is_scalar

// identity function if "is_scalar"
template<typename T, std::enable_if_t<std::is_scalar_v<T>, int> = 0>
inline T toScalarOrString(T v) {
  return v;
}

// outstream to std::string if not "is_scalar"
template<typename T, std::enable_if_t<!std::is_scalar_v<T>, int> = 0>
inline std::string toScalarOrString(const T& v) {
  std::ostringstream result;
  result << v;
  return result.str();
}

// identity function if "is_scalar"
template<typename T, std::enable_if_t<std::is_scalar_v<T>, int> = 0>
inline T toScalarOrChars(T v) {
  return v;
}

// obtain c-string if std::string
inline const char* toScalarOrChars(const std::string& v) {
  return v.c_str();
}

// usual safer snprintf call
template<typename... Ts>
inline std::string formatScalarOrString(const char* format_str, const Ts&... vs) {
  int size = std::snprintf(nullptr, 0, format_str, toScalarOrChars(vs)...);
  MY_ASSERT(size >= 0);
  std::string result;
  result.resize(size);
  std::snprintf(result.data(), size + 1, format_str, toScalarOrChars(vs)...);
  return result;
}

// This prevents calling snprintf without vararg, which triggers clang warnings.
inline std::string format(const char* fmtstr) {
  return std::string{fmtstr};
}

template<typename T, typename... Ts>
inline std::string format(const char* fmtstr, const T& v, const Ts&... vs) {
  return formatScalarOrString(fmtstr, toScalarOrString(v), toScalarOrString(vs)...);
}

template<typename... Ts>
inline void print(const char* fmtstr, const Ts&... vs) {
  std::printf("%s", format(fmtstr, vs...).c_str());
}

// const string& versions
template<typename... Ts>
inline std::string format(const std::string& fmtstr, const Ts&... vs) {
  return format(fmtstr.c_str(), vs...);
}

template<typename... Ts>
inline void print(const std::string& fmtstr, const Ts&... vs) {
  print(fmtstr.c_str(), vs...);
}

} // namespace utils


// Quick debug print macro
#define ddd(FORMAT, ...) \
  utils::print(string{"[debug:%s:%d] "} + FORMAT + "\n", string(__FILE__), __LINE__, __VA_ARGS__)
