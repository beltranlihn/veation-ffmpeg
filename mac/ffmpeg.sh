#!/usr/bin/env bash
# mac/ffmpeg.sh - compila FFmpeg 8.1.3 en el Mac desde el tarball verificado (FFMPEG-PROPIO.md, 2.5.4).
#
#   mac/ffmpeg.sh --fuentes <dir> --salida <dir>
#
# - configure recibe EXACTAMENTE la linea de piezas.conf (tools/piezas.sh args mac-<arch>), sin CFLAGS
#   ni LDFLAGS del entorno: asi -buildconf es toda la verdad de como se compilo;
# - el configure de 8.1.3 sigue pidiendo «-lsnappy -lstdc++» (linea 7381) y en macOS no hay libstdc++:
#   en vez de parchear FFmpeg, /tmp/vf/shim/libstdc++.tbd apunta al libc++.tbd del SDK y va en
#   --extra-ldflags (-L/tmp/vf/shim). El arbol de FFmpeg queda SIN MODIFICAR. Si el shim no sirviera,
#   el plan B es patches/reserva/ffmpeg-0001-snappy-libcxx.patch (patches/MODIFICACIONES.md);
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

# Reenlazado con traza
LDEXE="$(sed -n 's/^LDEXEFLAGS=//p' ffbuild/config.mak)"
rm -f ffmpeg_g ffprobe_g ffmpeg ffprobe
if ! env -u CFLAGS -u CXXFLAGS -u LDFLAGS make V=1 LDEXEFLAGS="$LDEXE -Wl,-t" ffmpeg_g ffprobe_g > "$SALIDA/enlazado.log" 2>&1; then
    tail -n 200 "$SALIDA/enlazado.log" >&2
    vf_die "el reenlazado con traza fallo"
fi
if grep -q 'built for newer macOS version' "$SALIDA/enlazado.log"; then
    grep 'built for newer macOS version' "$SALIDA/enlazado.log" >&2
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
