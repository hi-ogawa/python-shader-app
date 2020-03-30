import json
import numpy as np; Np = np.array


MAP_componentType = dict(zip(
  [5120, 5121, 5122, 5123, 5125, 5126],
  [np.int8, np.uint8, np.int16, np.uint16, np.uint32, np.float32]))

MAP_type = dict(zip(
  ['SCALAR', 'VEC2', 'VEC3', 'VEC4'],
  [1, 2, 3, 4]))


def np_from_accessor(index, gltf, buffer): # -> Np
  accessor = gltf['accessors'][index]
  bufferView = gltf['bufferViews'][accessor['bufferView']]
  data = buffer[bufferView['byteOffset']:][:bufferView['byteLength']]
  dtype = MAP_componentType[accessor['componentType']]
  num_component = MAP_type[accessor['type']]

  np_data = np.frombuffer(data, dtype)
  if num_component > 1:
    np_data = np_data.reshape((-1, num_component))

  return np_data


def np_from_primitive(primitive, gltf, buffer): # -> (Np, Dict[String, Np])
  indices = np_from_accessor(primitive['indices'], gltf, buffer)
  verts_dict = {}
  for key, value in primitive['attributes'].items():
    verts_dict[key] = np_from_accessor(value, gltf, buffer)
  return indices, verts_dict


def np_from_mesh(index, gltf, buffer): # -> List[(Np, Dict[String, Np])]
  mesh = gltf['meshes'][index]
  ps = mesh['primitives']
  ls = []
  for primitive in mesh['primitives']:
    ls.append(np_from_primitive(primitive, gltf, buffer))
  return ls


def load(gltf_file, buffer_file, mesh_index=0, primitive_index=0): # -> (verts_dict, faces)
  with open(gltf_file) as f:
    gltf = json.loads(f.read())

  with open(buffer_file, 'rb') as f:
    buffer = f.read()

  primitive = gltf['meshes'][mesh_index]['primitives'][primitive_index]
  indices, verts_dict = np_from_primitive(primitive, gltf, buffer)

  faces = indices.reshape((-1, 3)).astype(np.uint32)
  return verts_dict, faces
