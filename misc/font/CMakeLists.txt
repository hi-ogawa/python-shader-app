cmake_minimum_required(VERSION 3.0.0)
project(misc00 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS -fcolor-diagnostics)

#
# stb
#
add_library(stb SHARED src/stb_impl.cpp)
target_include_directories(stb PUBLIC thirdparty/stb)

#
# executable
#
add_executable(ex00_font_info src/ex00_font_info.cpp)
target_link_libraries(ex00_font_info PRIVATE stb)
