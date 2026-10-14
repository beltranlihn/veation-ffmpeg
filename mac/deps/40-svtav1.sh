# SVT-AV1 (export AV1 en 10 bits). Opciones de win/scripts.d/50-svtav1.sh.
PIEZA=svtav1
construir() {
    local extra=""
    [ "$VF_ARCH" = x86_64 ] && extra="-DENABLE_AVX512=ON"
    cmake -S . -B build -G Ninja $CMAKE_COMUN -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DBUILD_APPS=OFF \
        -DSVT_AV1_LTO=OFF $extra
    cmake --build build -j "$NPROC"
    cmake --install build
}
