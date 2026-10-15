#!/bin/bash

# >>> veation: bloque que escribe tools/aplicar-lock.sh desde versions.lock (no editar a mano)
SCRIPT_PIEZA="xz"
SCRIPT_REPO="https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.xz"
SCRIPT_SHA256="4ce24038fd4221e0d13bc1a2de7a4db56e90b92b3bf75321f6c14be73f65de4b"
# <<< veation

ffbuild_depends() {
    echo base
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # [veation] tarball de release: trae configure, no hace falta autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-symbol-versions
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
    echo --enable-lzma
}

ffbuild_unconfigure() {
    echo --disable-lzma
}
