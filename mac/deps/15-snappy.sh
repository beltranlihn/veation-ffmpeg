# snappy (obligatoria para el codificador hap). Opciones de win/scripts.d/50-snappy.sh.
PIEZA=snappy
construir() {
    cmake -S . -B build -G Ninja $CMAKE_COMUN \
        -DBUILD_SHARED_LIBS=OFF -DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF -DSNAPPY_FUZZING_BUILD=OFF \
        -DSNAPPY_REQUIRE_AVX=OFF -DSNAPPY_REQUIRE_AVX2=OFF
    cmake --build build -j "$NPROC"
    cmake --install build
}
