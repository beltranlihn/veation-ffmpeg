# [veation] Imagen con la toolchain cruzada de BtbN (crosstool-ng: GCC 16.2.0, binutils 2.47,
# mingw-w64 v14.0.0). Cambios (win/VEATION-CAMBIOS.md):
#   - crosstool-ng sale de SU archivo en fuentes/toolchain-win (el mismo que va al paquete de fuente y
#     que tools/fuentes-comprobar.sh verifica contra MANIFIESTO.tsv antes de compilar), no de un git
#     clone (BtbN clona su HEAD);
#   - los tarballs de la toolchain salen de la misma carpeta (contexto «vf-toolchain»); ct-ng-config
#     prohibe descargar (CT_FORBID_DOWNLOAD) y ct-ng comprueba ademas su sha512 contra los chksum de su
#     propio arbol;
#   - el paso entero corre SIN RED (--network=none): si ct-ng necesitase bajar algo, falla aqui. El
#     control negativo de verificar-fuente.yml quita gcc del paquete y exige «gcc: download failed»;
#   - sin rustup ni el destino de Rust.
ARG GH_REPO=vf.local/beltranlihn/veation-ffmpeg
ARG BASE_TAG_SUFFIX=
FROM $GH_REPO/base:latest${BASE_TAG_SUFFIX}

ARG CTNG_COMMIT
ARG CTNG_ARCHIVO

# El archivo no lleva .git: la version que ct-ng se da a si mismo (y que GCC graba como «crosstool-NG
# <version>» en cada objeto) sale de .tarball-version (maintainer/git-version-gen). Se toma de
# CT_VERSION de ct-ng-config, que tiene que acabar en los 7 primeros caracteres del commit del lock, y
# despues se comprueba que «ct-ng version» la imprime.
RUN --network=none \
    --mount=src=ct-ng-config,dst=/.config \
    --mount=type=bind,from=vf-toolchain,target=/ct-src \
    test -n "$CTNG_ARCHIVO" && test -f "/ct-src/$CTNG_ARCHIVO" && \
    CT_VER="$(sed -n 's/^CT_VERSION="\(.*\)"$/\1/p' /.config)" && \
    test -n "$CT_VER" && \
    test "${CT_VER##*_}" = "$(printf '%s' "$CTNG_COMMIT" | cut -c1-7)" && \
    mkdir /ct-ng && tar -xf "/ct-src/$CTNG_ARCHIVO" -C /ct-ng --strip-components=1 && cd /ct-ng && \
    printf '%s\n' "$CT_VER" > .tarball-version && \
    ./bootstrap && \
    ./configure --enable-local && \
    make -j$(nproc) && \
    ./ct-ng version | grep -F "$CT_VER" && \
    cp /.config .config && \
    ./ct-ng build && \
    cd / && \
    rm -rf ct-ng

# Prepare "cross" environment to heavily favour static builds
RUN \
    find /opt/ct-ng \( \
        -name "*.dll" \
        -or -name "*.dll.a" \
        \) -delete && \
    mkdir /opt/ffbuild

RUN \
    apt-get -y update && \
    apt-get -y install --no-install-recommends wine && \
    apt-get -y clean autoclean && \
    rm -rf /var/lib/apt/lists/*

ENV FFBUILD_TOOLCHAIN=x86_64-w64-mingw32

ADD toolchain.cmake /toolchain.cmake
ADD cross.meson /cross.meson

ENV PATH="/opt/ct-ng/bin:${PATH}" \
    FFBUILD_TARGET_FLAGS="--pkg-config=pkg-config --cross-prefix=${FFBUILD_TOOLCHAIN}- --arch=x86_64 --target-os=mingw32" \
    FFBUILD_CROSS_PREFIX=${FFBUILD_TOOLCHAIN}- \
    FFBUILD_PREFIX=/opt/ffbuild \
    FFBUILD_DESTDIR=/opt/ffdest \
    FFBUILD_DESTPREFIX=/opt/ffdest/opt/ffbuild \
    FFBUILD_CMAKE_TOOLCHAIN=/toolchain.cmake \
    PKG_CONFIG=pkg-config \
    PKG_CONFIG_LIBDIR=/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig \
    CC="${FFBUILD_TOOLCHAIN}-gcc" \
    CXX="${FFBUILD_TOOLCHAIN}-g++" \
    LD="${FFBUILD_TOOLCHAIN}-ld" \
    AR="${FFBUILD_TOOLCHAIN}-gcc-ar" \
    RANLIB="${FFBUILD_TOOLCHAIN}-gcc-ranlib" \
    NM="${FFBUILD_TOOLCHAIN}-gcc-nm" \
    DLLTOOL="${FFBUILD_TOOLCHAIN}-dlltool" \
    GENDEF="${FFBUILD_TOOLCHAIN}-gendef" \
    CFLAGS="-static-libgcc -static-libstdc++ -I/opt/ffbuild/include -O2 -pipe -D_FORTIFY_SOURCE=2 -fstack-protector-strong" \
    CXXFLAGS="-static-libgcc -static-libstdc++ -I/opt/ffbuild/include -O2 -pipe -D_FORTIFY_SOURCE=2 -fstack-protector-strong" \
    LDFLAGS="-static-libgcc -static-libstdc++ -L/opt/ffbuild/lib -O2 -pipe -fstack-protector-strong" \
    STAGE_CFLAGS="-fno-semantic-interposition" \
    STAGE_CXXFLAGS="-fno-semantic-interposition"
