#!/usr/bin/env bash
# mac/herramientas.sh - instala en /tmp/vf/herramientas las herramientas de compilacion del Mac,
# cada una en la version del lock y comprobada por sha256 (FFMPEG-PROPIO.md, 2.2):
#   CMake 3.31.x de Kitware (x265 4.1 no configura con CMake 4), meson desde su tarball, ninja,
#   pkgconf, GNU m4 + autoconf + automake + libtool (como glibtool) y, en x86_64, nasm.
# Se usan SIN modificar y no van al paquete de fuente. Es el UNICO paso del Mac que usa la red; despues
# mac/construir.sh compila sin ella.
#
#   mac/herramientas.sh            instala (idempotente: si ya estan en la version del lock, no hace nada)

. "$(dirname "$0")/entorno.sh"

vf_comprobar_xcode
mkdir -p "$VF_HERRAMIENTAS/bin" "$VF_DESCARGAS" "$VF_TRABAJO"
VERSIONES="$VF_HERRAMIENTAS/VERSIONES.txt"
FIRMA_LOCK="$(vf_lock_piezas mac herramienta | while read -r p; do printf '%s %s %s\n' "$p" "$(vf_lock_campo "$p" ref)" "$(vf_lock_campo "$p" sha256)"; done)"
if [ -f "$VERSIONES" ] && [ "$(sed -n '/^# lock$/,$p' "$VERSIONES" | sed 1d)" = "$FIRMA_LOCK" ]; then
    vf_log "herramientas ya instaladas en la version del lock"
    exit 0
fi

# bajar <pieza>: descarga el archivo del lock y comprueba su sha256. Imprime la ruta.
bajar() {
    local pieza="$1" url sha destino
    url="$(vf_lock_campo "$pieza" origen)"
    sha="$(vf_lock_campo "$pieza" sha256)"
    case "$sha" in PENDIENTE|"") vf_die "«$pieza» sin sha256 en el lock (congelar primero)" ;; esac
    destino="$VF_DESCARGAS/$(basename "$url")"
    if [ ! -f "$destino" ] || [ "$(vf_sha256 "$destino")" != "$sha" ]; then
        curl -fsSL --retry 5 --retry-delay 5 -o "$destino.part" "$url"
        mv "$destino.part" "$destino"
    fi
    [ "$(vf_sha256 "$destino")" = "$sha" ] || vf_die "«$pieza»: el sha256 de $(basename "$url") no es el del lock"
    printf '%s\n' "$destino"
}

# autotools <pieza> [opciones de configure]: tarball GNU estandar -> configure, make, make install
autotools() {
    local pieza="$1"; shift
    local tarball dir
    tarball="$(bajar "$pieza")"
    dir="$VF_TRABAJO/herramienta-$pieza"
    rm -rf "$dir"; mkdir -p "$dir"
    tar -xf "$tarball" -C "$dir" --strip-components=1
    (cd "$dir" && ./configure --prefix="$VF_HERRAMIENTAS" "$@" && make -j"$NPROC" && make install)
    rm -rf "$dir"
}

# CMake: binario universal de Kitware
t="$(bajar cmake-mac)"
rm -rf "$VF_HERRAMIENTAS/cmake"; mkdir -p "$VF_HERRAMIENTAS/cmake"
tar -xf "$t" -C "$VF_HERRAMIENTAS/cmake" --strip-components=1
for b in cmake ctest cpack; do ln -sf "$VF_HERRAMIENTAS/cmake/CMake.app/Contents/bin/$b" "$VF_HERRAMIENTAS/bin/$b"; done

# meson: se ejecuta desde su tarball con el python3 del sistema (Xcode)
t="$(bajar meson)"
rm -rf "$VF_HERRAMIENTAS/meson"; mkdir -p "$VF_HERRAMIENTAS/meson"
tar -xf "$t" -C "$VF_HERRAMIENTAS/meson" --strip-components=1
printf '#!/bin/sh\nexec /usr/bin/python3 %s/meson/meson.py "$@"\n' "$VF_HERRAMIENTAS" > "$VF_HERRAMIENTAS/bin/meson"
chmod 755 "$VF_HERRAMIENTAS/bin/meson"

# ninja: binario universal oficial
t="$(bajar ninja-mac)"
(cd "$VF_HERRAMIENTAS/bin" && rm -f ninja && unzip -o -q "$t" ninja && chmod 755 ninja)

# pkgconf (como pkg-config), sin mirar fuera del prefijo propio
autotools pkgconf --with-pkg-config-dir="$PREFIX/lib/pkgconfig" --with-system-libdir=/usr/lib --with-system-includedir=/usr/include
ln -sf pkgconf "$VF_HERRAMIENTAS/bin/pkg-config"

# GNU m4 (el /usr/bin/m4 de macOS es 1.4.6 y autoconf pide 1.4.8 o mas), autoconf, automake, libtool
autotools m4
autotools autoconf
autotools automake
autotools libtool --program-prefix=g

# nasm: solo lo necesitan las bibliotecas con ensamblador x86 (x264, x265, dav1d, libvpx, SVT-AV1, FFmpeg)
if [ "$VF_ARCH" = x86_64 ]; then
    autotools nasm
fi

{
    echo "# herramientas del Mac ($VF_SISTEMA), instaladas por mac/herramientas.sh"
    echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
    echo "sdk: $(xcrun --show-sdk-version) $(xcrun --show-sdk-path)"
    echo "clang: $(clang --version | head -1)"
    echo "cmake: $(cmake --version | head -1)"
    echo "meson: $(meson --version)"
    echo "ninja: $(ninja --version)"
    echo "pkg-config: $(pkg-config --version)"
    echo "m4: $(m4 --version | head -1)"
    echo "autoconf: $(autoconf --version | head -1)"
    echo "automake: $(automake --version | head -1)"
    echo "libtool: $(glibtool --version | head -1)"
    [ "$VF_ARCH" = x86_64 ] && echo "nasm: $(nasm -v)"
    echo "python3: $(/usr/bin/python3 --version)"
    echo "# lock"
    printf '%s\n' "$FIRMA_LOCK"
} > "$VERSIONES"
cat "$VERSIONES"
