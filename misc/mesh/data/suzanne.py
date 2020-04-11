#
# Create Monkey directly from Blender's source
#
# Usage:
#   python misc/mesh/data/suzanne.py > misc/mesh/data/suzanne.obj
#

import re
import numpy as np
import requests

url = 'https://github.com/blender/blender/blob/master/source/blender/bmesh/operators/bmo_primitive.c?raw=true'
resp = requests.get(url)

# parse vertex
m = re.search('monkeyv(.+?){(.*?)};', resp.text, re.DOTALL);
src = m.group(2)
ls = re.sub('\n|{|}|,|f', ' ', src).split()
v = np.array(list(map(float, ls))).reshape((-1, 3))

# process vertex
v += [127, 0, 0]
v /= 128

# parse face
m = re.search('monkeyf(.+?){(.*?)};', resp.text, re.DOTALL)
src = m.group(2)
ls = re.sub('\n|{|}|,|f', ' ', src).split()
f = np.array(list(map(int, ls))).reshape((-1, 4))

# process face
f += np.arange(len(f)).reshape((-1, 1)) - 4  # some mysterious encoding
f_tri = f[f[:, 2] == f[:, 3]][:, :3]
f_quad = f[f[:, 2] != f[:, 3]]
f_tri_from_quad = f_quad[..., [0, 1, 2, 0, 2, 3]].reshape((-1, 3))
f = np.concatenate([f_tri, f_tri_from_quad])

# mirror along x
v_mirror = v * [-1, 1, 1]
f_mirror = (f + len(v))[:, [2, 1, 0]]
non_mirror_indices = np.arange(len(v))[v[:, 0] == 0] + len(v)
f_mirror = np.vectorize(lambda i: i - (i in non_mirror_indices) * len(v))(f_mirror)
v = np.concatenate([v, v_mirror])
f = np.concatenate([f, f_mirror])

# export as .obj
for xyz in v:
    print('v', *xyz)

for abcd in (f + 1):  # obj face index
    print('f', *abcd)
