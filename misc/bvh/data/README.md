Download data from http://graphics.stanford.edu/data/3Dscanrep/

```
wget -c http://graphics.stanford.edu/pub/3Dscanrep/bunny.tar.gz
tar -C data -xzf data/bunny.tar.gz

wget -c http://graphics.stanford.edu/pub/3Dscanrep/dragon/dragon_recon.tar.gz
tar -C data -xzf data/dragon_recon.tar.gz

wget -c http://graphics.stanford.edu/pub/3Dscanrep/armadillo/Armadillo.ply.gz
gunzip --keep data/Armadillo.ply.gz

wget -c http://graphics.stanford.edu/data/3Dscanrep/xyzrgb/xyzrgb_dragon.ply.gz
gunzip --keep data/xyzrgb_dragon.ply.gz
```

Download data from assimp test (https://github.com/assimp/assimp)

```
wget -c https://raw.githubusercontent.com/assimp/assimp/master/test/models/OBJ/spider.obj
```


Download data from gltf samples (https://github.com/KhronosGroup/glTF-Sample-Models)

```
mkdir -p gltf/DamagedHelmet
URL_BASE=https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/DamagedHelmet/glTF
wget -P gltf/DamagedHelmet -c "${URL_BASE}"/DamagedHelmet.{gltf,bin}
wget -P gltf/DamagedHelmet -c "${URL_BASE}"/Default_{albedo,metalRoughness,emissive,AO,normal}.jpg
```
