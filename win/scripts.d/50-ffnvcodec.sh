#!/bin/bash

# >>> veation: bloque que escribe tools/aplicar-lock.sh desde versions.lock (no editar a mano)
SCRIPT_PIEZA="ffnvcodec"
SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT="1889e62e2d35ff7aa9baca2bceb14f053785e6f1"
# <<< veation

# [veation] Una sola rama de cabeceras, la decidida (piezas.conf: nvenc-cabeceras = n12.1.14.0, driver
# NVIDIA >= 531.61). BtbN elegia entre tres ramas segun la version de FFmpeg. Sin --enable-cuda-llvm:
# los filtros CUDA no se usan y meterian clang en la receta (FFMPEG-PROPIO.md, 3.2).

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && (( $(ffbuild_ffver) <= 801 )) && return -1
    (( $(ffbuild_ffver) >= 404 )) || return -1
    return 0
}

ffbuild_dockerbuild() {
    make PREFIX="$FFBUILD_PREFIX" DESTDIR="$FFBUILD_DESTDIR" install
}

ffbuild_configure() {
    echo --enable-ffnvcodec
}

ffbuild_unconfigure() {
    echo --disable-ffnvcodec
}

ffbuild_cflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}
