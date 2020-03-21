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
    loadPly(infile, vertices, indices);
    Bvh bvh = Bvh::create(vertices, indices, max_primitive);


    //
    // Emit statistics
    //
    {
      string text = R"(
num_vertices: %d
num_indices: %d
num_primitives: %d
num_nodes: %d
max_primitive: %d
)";
      std::ofstream ostr_stats{outfile + ".stats.yaml", std::ios::binary};
      ostr_stats << format(
          lstrip(text),
          vertices.size(),
          indices.size(),
          bvh.primitives.size(),
          bvh.nodes.size(),
          max_primitive
      );
    }

    //
    // Emit binary data
    //
    {
      std::ofstream ostr_data{outfile + ".node.bin", std::ios::binary};
      vector<BvhNode>& nodes = bvh.nodes;
      ostr_data.write((char*)nodes.data(), nodes.size() * sizeof(BvhNode));
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
