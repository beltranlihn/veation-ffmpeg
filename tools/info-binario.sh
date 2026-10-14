#!/usr/bin/env bash
# tools/info-binario.sh - vuelca lo que un binario de FFmpeg dice de si mismo, para que las puertas
# (tools/puertas.mjs), el manifiesto (tools/manifiesto.mjs) y BUILDINFO lo lean sin volver a ejecutarlo.
#
#   info-binario.sh <ffmpeg> <dir salida> [--ejecutor wine]
#
# Escribe en <dir>: version.txt licencia.txt buildconf.txt (normalizado: una opcion por linea, sin CR
# ni espacios sobrantes) encoders.txt decoders.txt filters.txt muxers.txt demuxers.txt formats.txt
# protocols.txt bsfs.txt hwaccels.txt sha256.txt. Con --ejecutor wine se corre dentro de la imagen
# base-win64 (tools/verificar-win.sh); en el Mac y en el runner de Windows, de forma nativa.
set -euo pipefail

FF="${1:?uso: info-binario.sh <ffmpeg> <dir> [--ejecutor wine]}"
DIR="${2:?falta el directorio de salida}"
EJ=()
if [ "${3:-}" = "--ejecutor" ]; then EJ=( "${4:?falta el ejecutor}" ); fi
mkdir -p "$DIR"

# ${EJ[@]+...}: con set -u, el bash 3.2 de macOS da «unbound variable» con un array vacio.
correr() { ${EJ[@]+"${EJ[@]}"} "$FF" -hide_banner "$@" 2>/dev/null | tr -d '\r'; }

correr -version > "$DIR/version.txt"
correr -L > "$DIR/licencia.txt"
correr -buildconf | awk '/configuration:/ { d = 1; next } d { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); if ($0 != "") print }' > "$DIR/buildconf.txt"
for l in encoders decoders filters muxers demuxers formats protocols bsfs hwaccels; do
    correr "-$l" > "$DIR/$l.txt"
done
if command -v sha256sum >/dev/null 2>&1; then sha256sum "$FF" | awk '{ print $1 }' > "$DIR/sha256.txt"
else shasum -a 256 "$FF" | awk '{ print $1 }' > "$DIR/sha256.txt"; fi

[ -s "$DIR/version.txt" ] || { echo "info-binario: $FF no respondio a -version" >&2; exit 1; }
[ -s "$DIR/buildconf.txt" ] || { echo "info-binario: -buildconf vacio" >&2; exit 1; }
