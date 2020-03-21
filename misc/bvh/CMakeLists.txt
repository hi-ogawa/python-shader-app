cmake_minimum_required(VERSION 3.0.0)
project(xxx LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS -fcolor-diagnostics)


#
# Libraries from thirdparty/
#

# - Catch2
add_library(catch thirdparty/Catch2/examples/000-CatchMain.cpp)
target_include_directories(catch PUBLIC thirdparty/Catch2/single_include)
target_compile_definitions(catch PUBLIC
  CATCH_CONFIG_ENABLE_BENCHMARKING=1)

# - glm
add_library(glm INTERFACE)
target_include_directories(glm INTERFACE thirdparty/glm)


#
# Global configuration
#
add_compile_definitions(
  CMAKE_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
  CMAKE_BINARY_DIR="${CMAKE_BINARY_DIR}" # NOTE: __FILE__ is a relative path wrt CMAKE_BINARY_DIR
)


#
# Executables
#
add_executable(ex00 src/ex00_test.cpp)
target_link_libraries(ex00 PRIVATE catch glm)

add_executable(ex01 src/ex01_benchmark.cpp)
target_link_libraries(ex01 PRIVATE catch glm)

add_executable(ex02 src/ex02_renderer_v2.cpp)
target_link_libraries(ex02 PRIVATE glm)

add_executable(ex03 src/ex03_test.cpp)
target_link_libraries(ex03 PRIVATE catch glm)

add_executable(ex04 src/ex04_exporter.cpp)
target_link_libraries(ex04 PRIVATE glm)
