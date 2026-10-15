#!/bin/bash

# >>> veation: bloque que escribe tools/aplicar-lock.sh desde versions.lock (no editar a mano)
SCRIPT_PIEZA="libxml2"
SCRIPT_REPO="https://github.com/GNOME/libxml2.git"
SCRIPT_COMMIT="96498992efa48d52b0e8b83058bd88dbdaf153c1"
# <<< veation

ffbuild_depends() {
    echo base
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --without-python
        --disable-maintainer-mode
        --disable-shared
        --enable-static
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./autogen.sh "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libxml2
}

ffbuild_unconfigure() {
    echo --disable-libxml2
}
