# libopus 1.6.1 (tarball de release: trae configure y los datos del modelo DNN). Opciones de
# win/scripts.d/50-libopus.sh.
PIEZA=opus
construir() {
    ./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-extra-programs --disable-doc
    make -j"$NPROC"
    make install
}
