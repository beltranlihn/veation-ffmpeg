#!/usr/bin/env bash
# tools/paquete-bajar.sh - baja SOLO el paquete de fuente de una release, lo verifica y lo extrae
# (verificar-fuente.yml, FFMPEG-PROPIO.md 2.5.6).
#
#   tools/paquete-bajar.sh <etiqueta> <dir>             de una release publicada
#   tools/paquete-bajar.sh --local <dir assets> <dir>   de los assets de una release AUN NO publicada
#                                                       (el artefacto «release» de build.yml)
#
# Comprueba cada parte contra SHA256SUMS de la release y el archivo entero contra el sha256 que
# publica SOURCE.txt (el mismo que llevan FFMPEG-NOTICES.txt y los zips). Deja el paquete extraido en
# <dir>/paquete (la raiz sirve como VF_FUENTES; la receta esta en <dir>/paquete/receta).
. "$(dirname "$0")/lib.sh"

ORIGEN=""
if [ "${1:-}" = "--local" ]; then
    ORIGEN="$(cd "${2:?dir con los assets}" && pwd)"; TAG="(local: $ORIGEN)"; DIR="${3:?dir}"
else
    TAG="${1:?etiqueta}"; DIR="${2:?dir}"
fi
mkdir -p "$DIR/descarga"; DIR="$(cd "$DIR" && pwd)"
cd "$DIR/descarga"
if [ -n "$ORIGEN" ]; then
    for f in "$ORIGEN"/*-source.tar.xz "$ORIGEN"/*-source.tar.xz.part* "$ORIGEN/SHA256SUMS" "$ORIGEN/SOURCE.txt"; do
        if [ -f "$f" ]; then cp "$f" .; fi
    done
else
    gh release download "$TAG" --repo "${GITHUB_REPOSITORY:-beltranlihn/veation-ffmpeg}" --clobber \
        -p '*-source.tar.xz' -p '*-source.tar.xz.part*' -p SHA256SUMS -p SOURCE.txt
fi
[ -f SHA256SUMS ] && [ -f SOURCE.txt ] || vf_die "$TAG: faltan SHA256SUMS o SOURCE.txt"
partes="$(ls | grep -E -- '-source\.tar\.xz(\.part[0-9]+)?$' | LC_ALL=C sort)"
[ -n "$partes" ] || vf_die "la release $TAG no tiene paquete de fuente"
for p in $partes; do
    sha="$(awk -v f="$p" '$2 == f { print $1 }' SHA256SUMS)"
    [ -n "$sha" ] || vf_die "$p no esta en SHA256SUMS"
    [ "$(vf_sha256 "$p")" = "$sha" ] || vf_die "$p no tiene el sha256 de SHA256SUMS"
done
base="$(echo "$partes" | head -1 | sed 's/\.part[0-9]*$//')"
[ -f "$base" ] || cat $partes > "$base"
esperado="$(grep -Eo "$base  SHA-256 [0-9a-f]{64}" SOURCE.txt | awk '{ print $3 }')"
[ -n "$esperado" ] || vf_die "SOURCE.txt no da el sha256 de $base"
[ "$(vf_sha256 "$base")" = "$esperado" ] || vf_die "el paquete unido no tiene el sha256 de SOURCE.txt"
rm -rf "$DIR/paquete"; mkdir -p "$DIR/paquete"
tar -xf "$base" -C "$DIR/paquete" --strip-components=1
vf_log "paquete $base verificado y extraido en $DIR/paquete"
