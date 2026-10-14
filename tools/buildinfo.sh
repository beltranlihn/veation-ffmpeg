#!/usr/bin/env bash
# tools/buildinfo.sh - BUILDINFO-<sistema>.txt: como se compilo un binario, para el paquete de fuente y
# la release (FFMPEG-PROPIO.md, 4.2 «build/»).
#
#   tools/buildinfo.sh <sistema> <dir info> <dir binarios> <salida> [archivo con datos de la toolchain]
#
# Recoge: version de la receta (commit), runner (ImageOS/ImageVersion), sha256 de cada binario,
# -version, -buildconf, -encoders, -decoders, -filters, -hwaccels, la linea de configure usada y los
# datos de la toolchain que le pase el job (gcc/binutils/mingw y digest de la imagen en Windows;
# Xcode, SDK y herramientas en el Mac).
. "$(dirname "$0")/lib.sh"

SIS="${1:?sistema}"; INFO="${2:?dir info}"; BIN="${3:?dir binarios}"; OUT="${4:?salida}"; EXTRA="${5:-}"
{
    echo "BUILDINFO $SIS - veation-ffmpeg $(vf_version)"
    echo "receta: ${GITHUB_REPOSITORY:-local}@$(git -C "$VF_RAIZ" rev-parse HEAD 2>/dev/null || echo '?') ${GITHUB_REF_NAME:-}"
    echo "runner: ${ImageOS:-?} ${ImageVersion:-?} ($(uname -sm))"
    echo "fecha: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "== sha256"
    for f in "$BIN"/ffmpeg "$BIN"/ffprobe "$BIN"/ffmpeg_g "$BIN"/ffprobe_g "$BIN"/ffmpeg.exe "$BIN"/ffprobe.exe "$BIN"/ffmpeg_g.exe "$BIN"/ffprobe_g.exe; do
        [ -f "$f" ] && echo "$(vf_sha256 "$f")  $(basename "$f")"
    done
    if [ -n "$EXTRA" ] && [ -f "$EXTRA" ]; then
        echo; echo "== toolchain"; cat "$EXTRA"
    fi
    for s in version buildconf encoders decoders filters hwaccels; do
        echo; echo "== -$s"; cat "$INFO/$s.txt"
    done
    if [ -f "$BIN/configure.args" ]; then
        echo; echo "== argumentos de configure (uno por linea, tal cual se pasaron)"; cat "$BIN/configure.args"
    fi
} > "$OUT"
vf_log "escrito $OUT"
