# xz / liblzma (tarball de release: trae configure). Opciones de win/scripts.d/25-xz.sh; ademas se
# apagan los programas y la traduccion, que no se enlazan.
PIEZA=xz
construir() {
    ./configure --prefix="$PREFIX" --disable-symbol-versions --disable-shared --enable-static --with-pic \
        --disable-nls --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc
    make -j"$NPROC"
    make install
}
