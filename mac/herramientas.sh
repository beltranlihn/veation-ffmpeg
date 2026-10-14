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
        vf_descargar "$url" "$destino.part"
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

# meson: se ejecuta desde su tarball con el python3 del sistema (el de Xcode 16.4 es 3.9.6; por eso el
# lock fija meson 1.11.2, que pide 3.7: desde la 1.12 meson.py exige 3.10 y sale con error)
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

# version_de <pieza del lock> <orden...>: ejecuta la orden, exige que funcione y que su salida diga la
# version del lock (ref), e imprime su primera linea. Se llama SIEMPRE en una asignacion propia: dentro
# del argumento de «echo», una sustitucion que falla no activa set -e (asi se colaba antes un meson que
# no arrancaba, con su mensaje de error guardado en VERSIONES.txt y el paso en verde).
version_de() {
    local pieza="$1" ref salida; shift
    ref="$(vf_lock_campo "$pieza" ref)"
    salida="$("$@" 2>&1)" || vf_die "«$pieza»: «$*» fallo: $(printf '%s\n' "$salida" | head -3 | tr '\n' ' ')"
    # la version tiene que aparecer como palabra entera (3.31.9 no vale para 3.31.90). Sin «grep -q» ni
    # «head»: con pipefail, un lector que cierra antes de tiempo puede dar SIGPIPE al que escribe y un
    # falso rojo; grep y sed leen hasta el final.
    printf '%s\n' "$salida" | tr -c '0-9.\n' ' ' | tr ' ' '\n' | grep -xF -- "$ref" > /dev/null \
        || vf_die "«$pieza»: «$*» dice «$(printf '%s\n' "$salida" | sed -n 1p)» y el lock pide $ref"
    printf '%s\n' "$salida" | sed -n 1p
}
v_cmake="$(version_de cmake-mac cmake --version)"
v_meson="$(version_de meson meson --version)"
v_ninja="$(version_de ninja-mac ninja --version)"
v_pkgconf="$(version_de pkgconf pkg-config --version)"
v_m4="$(version_de m4 m4 --version)"
v_autoconf="$(version_de autoconf autoconf --version)"
v_automake="$(version_de automake automake --version)"
v_libtool="$(version_de libtool glibtool --version)"
v_nasm=""
if [ "$VF_ARCH" = x86_64 ]; then v_nasm="$(version_de nasm nasm -v)"; fi
v_python="$(/usr/bin/python3 --version 2>&1)"

{
    echo "# herramientas del Mac ($VF_SISTEMA), instaladas por mac/herramientas.sh"
    echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
    echo "sdk: $(xcrun --show-sdk-version) $(xcrun --show-sdk-path)"
    echo "clang: $(clang --version | head -1)"
    echo "cmake: $v_cmake"
    echo "meson: $v_meson"
    echo "ninja: $v_ninja"
    echo "pkg-config: $v_pkgconf"
    echo "m4: $v_m4"
    echo "autoconf: $v_autoconf"
    echo "automake: $v_automake"
    echo "libtool: $v_libtool"
    if [ -n "$v_nasm" ]; then echo "nasm: $v_nasm"; fi
    echo "python3: $v_python"
    echo "# lock"
    printf '%s\n' "$FIRMA_LOCK"
} > "$VERSIONES"
cat "$VERSIONES"
