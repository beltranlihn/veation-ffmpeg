# dav1d (AV1 por software). Opciones de win/scripts.d/50-dav1d.sh.
PIEZA=dav1d
construir() {
    meson setup build --prefix="$PREFIX" --libdir=lib --buildtype=release --default-library=static --wrap-mode=nodownload
    ninja -C build -j "$NPROC"
    meson install -C build
}
