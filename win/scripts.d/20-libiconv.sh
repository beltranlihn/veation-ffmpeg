#!/bin/bash

# >>> veation: bloque que escribe tools/aplicar-lock.sh desde versions.lock (no editar a mano)
SCRIPT_PIEZA="libiconv"
SCRIPT_REPO="https://ftp.gnu.org/gnu/libiconv/libiconv-1.19.tar.gz"
SCRIPT_SHA256="PENDIENTE"
# <<< veation

ffbuild_enabled() {
    return 0
}


ffbuild_dockerbuild() {
    # [veation] tarball de release: trae configure, no hace falta autogen.sh ni gnulib

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-extra-encodings
        --disable-shared
        --enable-static
        --with-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-iconv
}

ffbuild_unconfigure() {
    echo --disable-iconv
}
