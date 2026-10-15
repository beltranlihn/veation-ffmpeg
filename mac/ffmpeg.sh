#!/usr/bin/env bash
# mac/ffmpeg.sh - compila FFmpeg 8.1.3 en el Mac desde el tarball verificado (FFMPEG-PROPIO.md, 2.5.4).
#
#   mac/ffmpeg.sh --fuentes <dir> --salida <dir>
#
# - configure recibe EXACTAMENTE la linea de piezas.conf (tools/piezas.sh args mac-<arch>), sin CFLAGS
#   ni LDFLAGS del entorno: asi -buildconf es toda la verdad de como se compilo;
# - el configure de 8.1.3 sigue pidiendo «-lsnappy -lstdc++» (linea 7381) y en macOS no hay libstdc++:
#   en vez de parchear FFmpeg, /tmp/vf/shim/libstdc++.tbd apunta al libc++.tbd del SDK y va en
#   --extra-ldflags (-L/tmp/vf/shim). El arbol de FFmpeg queda SIN MODIFICAR. Es el unico -lstdc++ que
#   llega: zimg.pc lleva -lc++ (mac/deps/45-zimg.sh, STL_LIBS) y x265.pc el -lc++ de su compilador. Si
#   el shim no sirviera, el plan B es patches/reserva/ffmpeg-0001-snappy-libcxx.patch
#   (patches/MODIFICACIONES.md);
# - tras compilar se REENLAZAN ffmpeg_g y ffprobe_g con -Wl,-t (traza del enlazador); el binario que
#   se publica es el de ese reenlazado;
# - strip, dsymutil (simbolos en ffmpeg_g.dSYM) y, como ULTIMO paso que toca los binarios, firma ad hoc.

. "$(dirname "$0")/entorno.sh"

FUENTES=""; SALIDA=""
while [ $# -gt 0 ]; do
    case "$1" in
        --fuentes) FUENTES="$2"; shift 2 ;;
        --salida)  SALIDA="$2"; shift 2 ;;
        *) vf_die "opcion desconocida: $1" ;;
    esac
done
[ -n "$FUENTES" ] && [ -n "$SALIDA" ] || vf_die "uso: mac/ffmpeg.sh --fuentes <dir> --salida <dir>"
FUENTES="$(cd "$FUENTES" && pwd)"
mkdir -p "$SALIDA"; SALIDA="$(cd "$SALIDA" && pwd)"

vf_comprobar_xcode

# shim libstdc++ -> libc++ del SDK
SDK="$(xcrun --show-sdk-path)"
[ -f "$SDK/usr/lib/libc++.tbd" ] || vf_die "no esta $SDK/usr/lib/libc++.tbd"
rm -rf "$VF_SHIM"; mkdir -p "$VF_SHIM"
ln -s "$SDK/usr/lib/libc++.tbd" "$VF_SHIM/libstdc++.tbd"

vf_extraer "$FUENTES" ffmpeg "$VF_FFMPEG_DIR"
cd "$VF_FFMPEG_DIR"

tools_piezas="$VF_RAIZ/tools/piezas.sh"
"$tools_piezas" args "$VF_SISTEMA" > "$SALIDA/configure.args"
set --
while IFS= read -r a; do set -- "$@" "$a"; done < "$SALIDA/configure.args"

# Sin CFLAGS/LDFLAGS del entorno (configure los recogeria sin que aparezcan en -buildconf).
if ! env -u CFLAGS -u CXXFLAGS -u LDFLAGS ./configure "$@" > "$SALIDA/configure.out" 2>&1; then
    cat "$SALIDA/configure.out" >&2
    tail -n 80 ffbuild/config.log >&2
    vf_die "configure fallo"
fi
cat "$SALIDA/configure.out"
cp ffbuild/config.log "$SALIDA/config.log"

env -u CFLAGS -u CXXFLAGS -u LDFLAGS make -j"$NPROC" V=1

# Reenlazado con traza. La traza (-Wl,-t) sale por stdout, con bufer; los avisos del enlazador, por
# stderr y sin el. Juntos en un archivo se cortaban a mitad de ruta (la build 38704005601 en x86_64:
# «.../MacOSX.platform/Developerld: warning: ...»), y una ruta partida se perdia sin que la puerta L1
# se enterase. Van a dos archivos: enlazado.log (lo que lee tools/enlazado.mjs) y enlazado-avisos.log.
LDEXE="$(sed -n 's/^LDEXEFLAGS=//p' ffbuild/config.mak)"
rm -f ffmpeg_g ffprobe_g ffmpeg ffprobe
if ! env -u CFLAGS -u CXXFLAGS -u LDFLAGS make V=1 LDEXEFLAGS="$LDEXE -Wl,-t" ffmpeg_g ffprobe_g > "$SALIDA/enlazado.log" 2> "$SALIDA/enlazado-avisos.log"; then
    tail -n 100 "$SALIDA/enlazado.log" "$SALIDA/enlazado-avisos.log" >&2
    vf_die "el reenlazado con traza fallo"
fi
# Objetos compilados para un macOS mas nuevo que el minimo. El enlazador de Xcode 15 y posteriores
# (ld-prime) escribe «was built for newer 'macOS' version (14.0) than being linked (13.0)», con
# comillas; el ld64 antiguo, sin ellas. El patron acepta las dos formas, y antes de fiarse de el se
# comprueba que caza el aviso de verdad: un objeto compilado para 14.0 enlazado con minimo 13.0.
AVISO_MINOS="built for newer '?macOS'? version"
cen="$(mktemp -d)"
printf 'int main(void) { return 0; }\n' > "$cen/c.c"
env -u CFLAGS -u LDFLAGS -u MACOSX_DEPLOYMENT_TARGET clang -mmacosx-version-min=14.0 -c "$cen/c.c" -o "$cen/c.o"
env -u CFLAGS -u LDFLAGS -u MACOSX_DEPLOYMENT_TARGET clang -mmacosx-version-min=13.0 "$cen/c.o" -o "$cen/c" > "$cen/ld.log" 2>&1 || true
if ! grep -Eq "$AVISO_MINOS" "$cen/ld.log"; then
    cat "$cen/ld.log" >&2
    vf_die "el centinela de minos no caza el aviso real del enlazador: revisar el patron «${AVISO_MINOS}»"
fi
rm -rf "$cen"
if grep -Eq "$AVISO_MINOS" "$SALIDA/enlazado-avisos.log" "$SALIDA/enlazado.log"; then
    grep -E "$AVISO_MINOS" "$SALIDA/enlazado-avisos.log" "$SALIDA/enlazado.log" >&2
    vf_die "hay objetos compilados para un macOS mas nuevo que $MACOS_MIN"
fi
env -u CFLAGS -u CXXFLAGS -u LDFLAGS make V=1 ffmpeg ffprobe

# Simbolos de depuracion (en macOS se quedan en los .o: dsymutil los recoge antes de borrar el arbol)
dsymutil ffmpeg_g -o "$SALIDA/ffmpeg_g.dSYM"
dsymutil ffprobe_g -o "$SALIDA/ffprobe_g.dSYM"

for b in ffmpeg ffprobe ffmpeg_g ffprobe_g; do
    cp "$b" "$SALIDA/$b"
    codesign --force --sign - "$SALIDA/$b"
done
cp COPYING.GPLv3 "$SALIDA/COPYING.GPLv3"
cp "$VF_HERRAMIENTAS/VERSIONES.txt" "$SALIDA/herramientas.txt" 2>/dev/null || true
vf_log "FFmpeg $VF_SISTEMA listo en $SALIDA"
