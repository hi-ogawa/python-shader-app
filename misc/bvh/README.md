Usage

```
# Update thirdparty/
git submodule update --init thirdparty/Catch2 thirdparty/glm

# Download mesh data (cf. http://graphics.stanford.edu/data/3Dscanrep/)
wget -P data -c http://graphics.stanford.edu/pub/3Dscanrep/bunny.tar.gz
tar -C data -xzf data/bunny.tar.gz

# Build
CC=clang CXX=clang++ LDFLAGS=-fuse-ld=lld \
  cmake -B build/Debug -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Debug
ninja -C build/Debug

# Run render
./build/Debug/ex02  -w 400 -h 400 --infile data/bunny/reconstruction/bun_zipper_res2.ply --outfile images/bunny2.ppm

# Run test
./build/Debug/ex00

# Run benchmark
./build/Debug/ex01
```
