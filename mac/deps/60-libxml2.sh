# libxml2 (demuxers IMF y DASH). Opciones de win/scripts.d/25-libxml2.sh; en el Mac usa el iconv y el
# zlib del sistema (FFMPEG-PROPIO.md, 3.1).
PIEZA=libxml2
construir() {
    ./autogen.sh --prefix="$PREFIX" --without-python --disable-maintainer-mode --disable-shared --enable-static
    make -j"$NPROC"
    make install
}
