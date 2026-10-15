#!/bin/bash

# >>> veation: bloque que escribe tools/aplicar-lock.sh desde versions.lock (no editar a mano)
SCRIPT_PIEZA="opus"
SCRIPT_REPO="https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz"
SCRIPT_SHA256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"
# <<< veation

ffbuild_enabled() {
    return 0
}


ffbuild_dockerbuild() {
    # [veation] tarball de release 1.6.1: ya trae los datos del modelo DNN (BtbN los bajaba con autogen.sh)
    # re-run autoreconf explicitly because tools versions might have changed since it generared the dl cache
    autoreconf -isf

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-extra-programs
    )

    if [[ $TARGET == winarm* ]]; then
        myconf+=(
            --disable-rtcd
        )
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libopus
}

ffbuild_unconfigure() {
    echo --disable-libopus
}
