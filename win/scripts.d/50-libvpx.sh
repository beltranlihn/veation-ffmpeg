#!/bin/bash

# >>> veation: bloque que escribe tools/aplicar-lock.sh desde versions.lock (no editar a mano)
SCRIPT_PIEZA="libvpx"
SCRIPT_REPO="https://chromium.googlesource.com/webm/libvpx"
SCRIPT_COMMIT="1024874c5919305883187e2953de8fcb4c3d7fa6"
# <<< veation

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    local myconf=(
        --disable-shared
        --enable-static
        --enable-pic
        --disable-examples
        --disable-tools
        --disable-docs
        --disable-unit-tests
        --enable-vp9-highbitdepth
        --prefix="$FFBUILD_PREFIX"
    )

    if [[ $TARGET == win64 ]]; then
        myconf+=(
            --target=x86_64-win64-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    elif [[ $TARGET == win32 ]]; then
        myconf+=(
            --target=x86-win32-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    elif [[ $TARGET == winarm64 ]]; then
        myconf+=(
            --target=arm64-win64-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    elif [[ $TARGET == linux64 ]]; then
        myconf+=(
            --target=x86_64-linux-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    elif [[ $TARGET == linuxarm64 ]]; then
        myconf+=(
            --target=arm64-linux-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    else
        echo "Unknown target"
        return -1
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Work around strip breaking LTO symbol index
    "$RANLIB" "$FFBUILD_DESTPREFIX"/lib/libvpx.a
}

ffbuild_configure() {
    echo --enable-libvpx
}

ffbuild_unconfigure() {
    echo --disable-libvpx
}
