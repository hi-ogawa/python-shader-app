/*

NOTE:

Exported BVH can be read from python by

```python
import numpy as np

bvh_node_dtype_fields = [
    ('bbox', 'float32', (2, 3)),
    ('begin', 'uint32'),
    ('num_primitives', 'uint8'),
    ('axis', 'uint8')
]
bvh_node_dtype = np.dtype(bvh_node_dtype_fields, align=True)
assert bvh_node_dtype.itemsize == 32

file = 'tmp.bin'
nodes = np.fromfile(file, dtype=bvh_node_dtype)
print(len(nodes))
```

*/


#include <fstream>
#include <tuple>

#include "utils/ply.hpp"
#include "utils/bvh.hpp"
#include "utils/misc.hpp"


using std::string, std::vector;
using namespace utils;


struct Exporter {
  string infile;
  string outfile;
  int max_primitive;
  vector<fvec3> vertices;
  vector<uvec3> indices;

  void run() {
    //
    // Construct BVH
    //
    loadPly(infile, vertices, indices);
    Bvh bvh = Bvh::create(vertices, indices, max_primitive);

    //
    // Emit data and statistics
    //

    // name, p_data, len, itemsize
    vector<std::tuple<string, char*, size_t, size_t>> vec = {
        #define TUPLE(NAME, VECTOR) \
            {#NAME, (char*)VECTOR.data(), VECTOR.size(), sizeof(VECTOR[0])}
        TUPLE(vertex,    vertices),
        TUPLE(index,     indices),
        TUPLE(primitive, bvh.primitives),
        TUPLE(node,      bvh.nodes),
        #undef TUPLE
    };

    std::ofstream ostr_stats{outfile + ".stats.yaml"};
    string yaml_template = lstrip(R"(
%s:
  len: %d
  itemsize: %d
  nbytes: %d
)");

    for (auto& [name, p_data, len, itemsize] : vec) {
      std::ofstream ostr{outfile + "." + name + ".bin", std::ios::binary};
      size_t nbytes = len * itemsize;

      // Emit statistics
      ostr_stats << format(yaml_template, name, len, itemsize, nbytes);

      // Emit binary data
      ostr.write(p_data, len * itemsize);
    }
  }
};

int main(int argc, const char** argv) {
  Cli cli{argc, argv};
  auto infile  = cli.getArg<string>("--infile");
  auto outfile = cli.getArg<string>("--outfile");
  int max_primitive = cli.getArg<int>("--max-primitive").value_or(2);
  if (!(infile && outfile)) {
    print(cli.help());
    return 1;
  }

  Exporter{*infile, *outfile, max_primitive}.run();
  return 0;
}
