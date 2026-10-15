#!/bin/bash

# >>> veation: bloque que escribe tools/aplicar-lock.sh desde versions.lock (no editar a mano)
SCRIPT_PIEZA="zimg"
SCRIPT_REPO="https://github.com/sekrit-twc/zimg.git"
SCRIPT_COMMIT="f819b14e8f39d1282400b0d9543e8ef73c1b2bbd"
# <<< veation

ffbuild_enabled() {
    return 0
}


ffbuild_dockerbuild() {
    sed -i '1i #include <exception>' src/zimg/api/zimg.cpp

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
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
    echo --enable-libzimg
}

ffbuild_unconfigure() {
    echo --disable-libzimg
}
