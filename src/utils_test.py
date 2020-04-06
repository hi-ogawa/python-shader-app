import unittest, os, tempfile
from .utils import preprocess_include, preprocess_source


class TestUtils(unittest.TestCase):
  def test_misc00(self):
    example = """\
a
%%EVAL: 1 + 1 %% b
  c %%EVAL: 2**10 %% %%EVAL: 4 % 3 %%
      %%EVAL: 'abc' %%
  %%EXEC:
    RESULT = 0
    for i in range(8):
      RESULT += 2
  %%
d
%%EVAL: None %% e
"""
    expected = """\
a
2 b
  c 1024 1
      abc
  16
d
None e
"""
    result = preprocess_source(example)
    self.assertEqual(result, expected)


  def test_preprocess_include_ex1(self):
    includer = """\
// includer start
#include "includee1.glsl"
// after includee1

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  float fac = myFunc(frag_coord.x / iResolution.x);
  frag_color = vec4(vec3(fac), 1.0);
}
"""

    includee1 = """\
// includee1 start
#define M_PI 3.14
#include "includee2.glsl"
// after includee2

float myFunc1(float t) {
  return myFunc2(t);
}
"""

    includee2 = """\
// includee2 start
float myFunc2(float t) {
  return (-2.0 * t + 3.0) * t * t;
}
"""

    expected_result = """\
#line 1
// includer start
#line 1
// includee1 start
#define M_PI 3.14
#line 1
// includee2 start
float myFunc2(float t) {
  return (-2.0 * t + 3.0) * t * t;
}
#line 4
// after includee2

float myFunc1(float t) {
  return myFunc2(t);
}
#line 3
// after includee1

void mainImage(out vec4 frag_color, vec2 frag_coord) {
  float fac = myFunc(frag_coord.x / iResolution.x);
  frag_color = vec4(vec3(fac), 1.0);
}
"""

    with tempfile.TemporaryDirectory() as tmpdir:
      includer_file = os.path.join(tmpdir, "includer.glsl")
      includee1_file = os.path.join(tmpdir, "includee1.glsl")
      includee2_file = os.path.join(tmpdir, "includee2.glsl")

      with open(includer_file, 'w') as f: f.write(includer)
      with open(includee1_file, 'w') as f: f.write(includee1)
      with open(includee2_file, 'w') as f: f.write(includee2)

      result, included_files = preprocess_include(includer_file, add_line_directive=True)
      self.assertEqual(result, expected_result)
      self.assertEqual(included_files, [includee1_file, includee2_file])
