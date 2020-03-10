#pragma once

#include <vector>
#include <string>
#include <stdexcept>
#include <sstream>

#define MY_ASSERT(EXPR)                                             \
  if(!static_cast<bool>(EXPR)) {                                    \
    std::ostringstream ostream;                                     \
    ostream << "[" << __FILE__ << ":" << __LINE__ << "] " << #EXPR; \
    throw std::runtime_error{ostream.str()};                        \
  }                                                                 \


// Overload stream operator for std containers
namespace std {

template<typename T>
inline std::ostream& operator<<(std::ostream& os, const std::vector<T>& v) {
  os << "{";
  for (auto i = 0; i < v.size(); i++) {
    if (i > 0) os << ", ";
    os << v[i];
  }
  os << "}";
  return os;
}

} // namespace std
