#!/usr/bin/env bash
# mac-r475/construir.sh - FFmpeg para el Mac (arm64) de VEATION, compilado desde fuente FIJADA (R475).
#
# La misma versión que el de Windows (FFmpeg n8.1.3-18-g46d899d7a0, rama release/8.1) y la línea de configure de R408
# (videotoolbox, audiotoolbox, neon, gpl, version3, sin ffplay/sdl2/doc/debug) con SÓLO cuatro bibliotecas, todas
# compiladas aquí desde su commit (nada de Homebrew dentro del binario): x264, x265 (8+10+12 bits: la app exporta
# HEVC Main 10 con libx265), libvpx y snappy (el codificador HAP). Los commits son los MISMOS que lleva el ffmpeg.exe
# de Windows (su FUENTES.tsv). Estático; macOS mínimo 12.0.
#
#   mac-r475/construir.sh <carpeta de trabajo> <commit de esta receta>
#
# Deja en <trabajo>/salida/: ffmpeg, buildconf.txt, version.txt y el paquete de fuente
#   ffmpeg-n8.1.3-18-g46d899d7a0-macos-arm64-gpl-r475-source.tar.xz (+ .sha256): la receta, el fuente de cada pieza
#   tal cual se bajó (sin .git), FUENTES.tsv (con el commit resuelto) y checksums.sha256.
set -euo pipefail

TRABAJO="$(mkdir -p "$1" && cd "$1" && pwd)"; RECETA_COMMIT="$2"
RECETA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export MACOSX_DEPLOYMENT_TARGET=12.0
NPROC="$(sysctl -n hw.ncpu)"
VERSION=n8.1.3-18-g46d899d7a0
NOMBRE="ffmpeg-${VERSION}-macos-arm64-gpl-r475-source"
S="$TRABAJO/src"; P="$TRABAJO/prefix"; O="$TRABAJO/salida"; PKG="$TRABAJO/paquete/$NOMBRE"
rm -rf "$S" "$P" "$O" "$TRABAJO/paquete"; mkdir -p "$S" "$P" "$O" "$PKG/fuentes"

printf 'etapa\trepositorio\tcommit_o_revision\tcarpeta\tcommit_resuelto\n' > "$PKG/FUENTES.tsv"
# pieza url commit carpeta-en-el-paquete: clona, comprueba que HEAD es el commit pedido y copia el árbol SIN .git al paquete
pieza() {
    local n="$1" url="$2" c="$3" dest="$4"
    git clone -q --filter=blob:none "$url" "$S/$n"
    git -C "$S/$n" -c advice.detachedHead=false checkout -q "$c"
    local h; h="$(git -C "$S/$n" rev-parse HEAD)"
    [ "$h" = "$c" ] || { echo "*** $n está en $h, no en $c" >&2; exit 1; }
    mkdir -p "$PKG/$dest"; rsync -a --exclude .git "$S/$n/" "$PKG/$dest/"
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$url" "$c" "$dest" "$h" >> "$PKG/FUENTES.tsv"
}
pieza x264   https://code.videolan.org/videolan/x264.git       0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee fuentes/x264
pieza x265   https://github.com/Multicorewareinc/x265.git      020d7054dbecfd3be8e62efe33ff8a305d41856e fuentes/x265
pieza libvpx https://chromium.googlesource.com/webm/libvpx    5e680f30801d03c21078f8c4b772464752516211 fuentes/libvpx
pieza snappy https://github.com/google/snappy.git              9c28114a38866f6deeaa826db918293bc28ae410 fuentes/snappy
pieza ffmpeg https://github.com/FFmpeg/FFmpeg.git              46d899d7a02bc63237472cc4897258d5ddf274ac ffmpeg
printf '%s\t%s\t%s\t%s\t%s\n' 'veation-ffmpeg (receta)' 'https://github.com/beltranlihn/veation-ffmpeg.git' "$RECETA_COMMIT" 'receta' "$RECETA_COMMIT" >> "$PKG/FUENTES.tsv"
mkdir -p "$PKG/receta"; rsync -a --exclude .git --exclude trabajo "$RECETA_DIR/" "$PKG/receta/"

# SÓLO nuestro prefijo: con PKG_CONFIG_PATH, pkg-config veía también el Homebrew del runner y FFmpeg se autodetectaba su libxcb
# (la primera ejecución, 39640927039, salió enlazada a /opt/homebrew/opt/libxcb: lo cazó comprobar.sh)
export PKG_CONFIG_LIBDIR="$P/lib/pkgconfig"; unset PKG_CONFIG_PATH
CM=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_POLICY_VERSION_MINIMUM=3.5)

# ---- x264
( cd "$S/x264" && ./configure --prefix="$P" --enable-static --disable-cli --enable-pic && make -j"$NPROC" && make install )

# ---- x265, multilib 8+10+12 (como Homebrew y como el de Windows): libx265 tiene que dar Main 10 con p010le
X=$S/x265/source
cmake -S "$X" -B "$S/x265-12" "${CM[@]}" -DHIGH_BIT_DEPTH=ON -DMAIN12=ON -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_ASSEMBLY=OFF
cmake --build "$S/x265-12" -j"$NPROC"
cmake -S "$X" -B "$S/x265-10" "${CM[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_ASSEMBLY=OFF
cmake --build "$S/x265-10" -j"$NPROC"
mkdir -p "$S/x265-8"
cp "$S/x265-12/libx265.a" "$S/x265-8/libx265_main12.a"; cp "$S/x265-10/libx265.a" "$S/x265-8/libx265_main10.a"
cmake -S "$X" -B "$S/x265-8" "${CM[@]}" -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
    -DEXTRA_LIB="x265_main10.a;x265_main12.a" -DEXTRA_LINK_FLAGS=-L.
cmake --build "$S/x265-8" -j"$NPROC"
( cd "$S/x265-8" && mv libx265.a libx265_main.a && libtool -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a )
cmake --install "$S/x265-8"

# ---- libvpx (el decodificador libvpx-vp9 que usa la app; alta profundidad como el de Windows)
( mkdir -p "$S/vpx-b" && cd "$S/vpx-b" && "$S/libvpx/configure" --prefix="$P" --enable-static --disable-shared --enable-pic \
    --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth && make -j"$NPROC" && make install )

# ---- snappy (el codificador HAP)
cmake -S "$S/snappy" -B "$S/snappy-b" "${CM[@]}" -DBUILD_SHARED_LIBS=OFF -DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF
cmake --build "$S/snappy-b" -j"$NPROC"; cmake --install "$S/snappy-b"

# sólo bibliotecas estáticas en el prefijo: que el enlazador no pueda coger una dylib
find "$P/lib" -name '*.dylib' -delete

# ---- FFmpeg. Su configure pide «-lsnappy -lstdc++» y en macOS no hay libstdc++: en vez de parchear FFmpeg (el fuente
# queda SIN MODIFICAR), un libstdc++.tbd que apunta al libc++.tbd del SDK, en una carpeta que va en --extra-ldflags.
SHIM="$TRABAJO/shim"; rm -rf "$SHIM"; mkdir -p "$SHIM"; ln -s "$(xcrun --show-sdk-path)/usr/lib/libc++.tbd" "$SHIM/libstdc++.tbd"
cd "$S/ffmpeg"
./configure --cc=clang --enable-gpl --enable-version3 --disable-shared --enable-static --enable-pthreads \
    --enable-videotoolbox --enable-audiotoolbox --enable-neon --enable-libx264 --enable-libx265 --enable-libvpx \
    --enable-libsnappy --disable-ffplay --disable-sdl2 --disable-doc --disable-debug --disable-libxcb --disable-xlib --pkg-config-flags=--static \
    --extra-cflags="-I$P/include -mmacosx-version-min=12.0" --extra-ldflags="-L$P/lib -L$SHIM -mmacosx-version-min=12.0" \
    --extra-version=veation-r475 || { tail -n 80 ffbuild/config.log; exit 1; }
make -j"$NPROC"
strip -x ffmpeg -o "$O/ffmpeg"
codesign --force --sign - "$O/ffmpeg"
"$O/ffmpeg" -hide_banner -buildconf > "$O/buildconf.txt"
"$O/ffmpeg" -hide_banner -version | head -1 > "$O/version.txt"

# ---- el paquete de fuente
cd "$TRABAJO/paquete"
cat > "$NOMBRE/RECETA.md" <<EOF
# Código fuente del FFmpeg de VEATION para macOS (arm64), ${VERSION}

Fuente completo y correspondiente del binario \`ffmpeg\` que VEATION lleva en su .app de macOS (Apple Silicon).
- **Receta**: \`receta/\` = la rama \`mac-8.1-r475\` de https://github.com/beltranlihn/veation-ffmpeg en el commit \`${RECETA_COMMIT}\`
  (\`mac-r475/construir.sh\` y \`.github/workflows/mac-r475.yml\`). Compila en GitHub Actions, macos-15 arm64, macOS mínimo 12.0.
- **FFmpeg**: \`ffmpeg/\`, commit 46d899d7a02bc63237472cc4897258d5ddf274ac (rama release/8.1). **Sin modificar**: el \`-lstdc++\`
  que su configure pide para libsnappy se resuelve con un \`libstdc++.tbd\` que apunta al \`libc++.tbd\` del SDK (ver la receta).
- **Bibliotecas** (\`fuentes/\`): x264, x265 (8, 10 y 12 bits), libvpx y snappy, cada una a su commit (\`FUENTES.tsv\`), las mismas
  que el ffmpeg.exe de Windows. Copiadas tal cual se bajaron, sin \`.git\`.
- Además enlaza con bibliotecas del sistema de macOS (VideoToolbox, AudioToolbox, CoreMedia, libc++, …), que no se incluyen.
- \`checksums.sha256\`: el sha256 de cada archivo.

Reconstruir en un Mac arm64 con Xcode, cmake y pkg-config: \`receta/mac-r475/construir.sh <carpeta> <commit de la receta>\`
(clona las piezas de sus repositorios a los mismos commits; para hacerlo sin red, poner esas carpetas en \`<carpeta>/src/\`).
EOF
( cd "$NOMBRE" && find . -type f ! -name checksums.sha256 | LC_ALL=C sort | sed 's#^\./##' | while IFS= read -r f; do shasum -a 256 "$f"; done > checksums.sha256 )
tar -cf - "$NOMBRE" | xz -T0 -6 > "$O/$NOMBRE.tar.xz"
( cd "$O" && shasum -a 256 "$NOMBRE.tar.xz" > "$NOMBRE.tar.xz.sha256" )
echo "listo: $O"
