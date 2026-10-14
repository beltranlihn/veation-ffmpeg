# x264. Opciones de win/scripts.d/50-x264.sh (incluido --disable-opencl, en los dos sistemas).
PIEZA=x264
construir() {
    ./configure --prefix="$PREFIX" --disable-cli --enable-static --enable-pic --disable-lavf --disable-swscale \
        --disable-opencl --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS"
    make -j"$NPROC"
    make install
}
