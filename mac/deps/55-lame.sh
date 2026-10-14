# LAME 3.100 (tarball de release). Opciones de win/scripts.d/50-libmp3lame.sh. --build explicito: el
# config.guess de 2017 no conoce los Mac con Apple Silicon.
PIEZA=lame
construir() {
    local build
    case "$VF_ARCH" in arm64) build=aarch64-apple-darwin ;; x86_64) build=x86_64-apple-darwin ;; esac
    CFLAGS="$CFLAGS -DNDEBUG" ./configure --prefix="$PREFIX" --build="$build" --host="$build" \
        --disable-shared --enable-static --disable-cpml --disable-frontend --disable-decoder
    make -j"$NPROC"
    make install
}
