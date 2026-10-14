#!/bin/bash

# >>> veation: bloque que escribe tools/aplicar-lock.sh desde versions.lock (no editar a mano)
SCRIPT_PIEZA="bzip2"
SCRIPT_REPO="https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz"
SCRIPT_SHA256="PENDIENTE"
# <<< veation

# [veation] Script NUEVO (BtbN no tiene bzip2). gyan lo lleva (--enable-bzlib) y FFmpeg lo usa para las
# pistas comprimidas con bzip2 de MKV; sin este script, el --enable-bzlib de piezas.conf haria fallar
# configure con «bzlib requested but not found». bzip2 1.0.8 no trae configure: solo se compila
# libbz2.a con su Makefile, sin modificar el fuente. En _WIN32, bzlib.h declara las funciones como
# funciones normales salvo que se defina BZ_IMPORT (que nadie define), asi que el enlace estatico vale
# tal cual.

ffbuild_enabled() {
    [[ $TARGET == win* ]] || return -1
    return 0
}

ffbuild_dockerbuild() {
    make -j$(nproc) CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        CFLAGS="$CFLAGS -Wall -Winline -D_FILE_OFFSET_BITS=64" libbz2.a

    install -D -m644 bzlib.h "$FFBUILD_DESTPREFIX/include/bzlib.h"
    install -D -m644 libbz2.a "$FFBUILD_DESTPREFIX/lib/libbz2.a"
}

ffbuild_configure() {
    echo --enable-bzlib
}

ffbuild_unconfigure() {
    echo --disable-bzlib
}
