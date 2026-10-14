# libvpx (decodificador libvpx-vp9: el unico que entrega el alfa del .webm). Opciones de
# win/scripts.d/50-libvpx.sh. El destino darwin22 corresponde a macOS 13; desde darwin20 libvpx solo
# anade -arch, el minimo sale de MACOSX_DEPLOYMENT_TARGET y de CFLAGS.
PIEZA=libvpx
construir() {
    ./configure --prefix="$PREFIX" --target="$VPX_TARGET" --disable-shared --enable-static --enable-pic \
        --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth
    if [ "$VF_ARCH" = arm64 ] && ! grep -q '^#define HAVE_NEON 1' vpx_config.h; then
        vf_die "libvpx se configuro sin NEON en arm64"
    fi
    make -j"$NPROC"
    make install
}
