#include <catch2/catch.hpp>

#include "utils/common.hpp"
#include "utils/misc.hpp"

TEST_CASE("misc") {
  using std::string, std::vector;

  // vector format
  {
    vector<string> result = {"abc", "def", "xyz"};
    REQUIRE(utils::format("%s", result) == "{abc, def, xyz}");
  }

  // b_find
  {
    int i = 2;
    REQUIRE(utils::b_find({0, 1, 2, 3}, i));
    REQUIRE(utils::b_find({0, 1, 2, 3}, 2));
    REQUIRE(!utils::b_find({0, 1, 2, 3}, 4));
  }
}


TEST_CASE("string") {
  using std::string, std::vector;
  using namespace utils;

  REQUIRE(slice("abcde", 0, 3) == "abc");
  REQUIRE(slice("abcde", 3, 0) == "de");
  REQUIRE(slice("abcde", -2, 0) == "de");

  REQUIRE(index("abcde", "bc") == 1);
  REQUIRE(index("abcde", "bd") == -1);
  REQUIRE(index("", "a") == -1);

  {
    vector<string> result = split("abc: def: xyz", ": ");
    REQUIRE(result.size() == 3);
    REQUIRE(result[0] == "abc");
    REQUIRE(result[1] == "def");
    REQUIRE(result[2] == "xyz");
  }

  {
    vector<string> result = split("", ": ");
    REQUIRE(result.size() == 1);
    REQUIRE(result[0] == "");
  }
}


TEST_CASE("Rng") {
  using namespace utils;

  Rng rng{0x12341234, 0x56785678};

  // Very rough uniformity test
  int num_samples = 1000;
  int num_bins = 100;
  vector<int> histogram;  histogram.resize(num_bins);
  for (auto i = 0; i < num_samples; i++) {
    float f = rng.uniform();
    int bin_idx = (int)floor(num_bins * f);
    histogram[bin_idx] += 1;
  }
  CHECK(!b_find(histogram, 0));
}


TEST_CASE("Yeml") {
  using std::string, std::vector;
  using namespace utils;

  {
    string ex = R"(
a:
  b: c
  d: e
)";
    Yeml y = Yeml::parse(ex);
    REQUIRE(y.isDict());
    REQUIRE(y["a"].isDict());
    REQUIRE(y["a"]["b"].isStr());
    REQUIRE(y.d("a"));
    REQUIRE(!y.d("A"));
    REQUIRE(y["a"]["b"].s() == "c");
    REQUIRE(y["a"]("b") == "c");
    REQUIRE(y["a"].ds("d").value() == "e");

    CHECK_THROWS_WITH(y["A"], "KeyError: A");
    CHECK_THROWS_WITH(y["a"]("B"), "KeyError: B");
    CHECK_THROWS_WITH(y("a"), R"(TypeError: key ["a"] not string)");
  }

  {
    string ex = R"(
a0:
  - k0: v0
    k1: v1
  -
    k0: v0
    k1: v1
    k2:
      k2-1: v0
      k2-2: v1
a1:
  - v0
  - v1
)";
    Yeml y = Yeml::parse(ex, /*debug*/ false);
    REQUIRE(y.isDict());
    REQUIRE(y["a0"].isList());
    REQUIRE(y["a0"][1]["k0"].s() == "v0");
    REQUIRE(y["a1"].ds(0) == "v0");
    REQUIRE(y["a1"].ds(1) == "v1");
    REQUIRE(y["a1"](1) == "v1");

    CHECK_THROWS_WITH(y["a1"](2), "IndexError: 2");
    CHECK_THROWS_WITH(y["a0"](0), "TypeError: index [0] not string");
  }

  {
    string ex;

    ex = R"(
a
b
)";
    CHECK_THROWS_WITH(Yeml::parse(ex), "SyntaxError: not all input consumed");

    ex = R"(
a: b
c
)";
    CHECK_THROWS_WITH(Yeml::parse(ex), R"(SyntaxError: unexpected line "c")");

    ex = R"(
- a
c: d
)";
    CHECK_THROWS_WITH(Yeml::parse(ex), R"(SyntaxError: unexpected line "c: d")");

      ex = R"(
c: d
- a
)";
    CHECK_THROWS_WITH(Yeml::parse(ex), R"(SyntaxError: unexpected line "- a")");
  }
}

TEST_CASE("Yeml format") {
  using std::string, std::vector;
  using namespace utils;

  {
    string example = R"(
a0:
  - k0: v0
    k1: v1
  -
    k0: v0
    k2:
      k2-1: v0
a1:
  - v0
)";

    string expected = lstrip(R"(
a0:
  -
    k0: v0
    k1: v1
  -
    k0: v0
    k2:
      k2-1: v0
a1:
  - v0
)");
    Yeml y = Yeml::parse(example);
    REQUIRE(format("%s", y) == expected);
  }
}

TEST_CASE("Yeml string literal") {
  using std::string, std::vector;
  using namespace utils;

  {
    string ex = R"(x: "abcde")";
    REQUIRE(format("%s", Yeml::parse(ex)) == "x: \"abcde\"\n");
  }
}
