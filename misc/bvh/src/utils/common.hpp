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
