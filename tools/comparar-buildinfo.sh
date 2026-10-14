#!/usr/bin/env bash
# tools/comparar-buildinfo.sh - la reconstruccion desde el paquete de fuente da el MISMO binario que la
# release, en lo que el binario dice de si mismo: -version, -buildconf, -encoders y -decoders
# (FFMPEG-PROPIO.md, 2.5.6, paso 3).
#
#   tools/comparar-buildinfo.sh <BUILDINFO-<sistema>.txt de la release> <dir info de la reconstruccion>
. "$(dirname "$0")/lib.sh"

BI="${1:?BUILDINFO}"; INFO="${2:?dir info}"
fallos=0
for s in version buildconf encoders decoders; do
    awk -v s="== -$s" '$0 == s { d = 1; next } /^== / { d = 0 } d' "$BI" | sed -e '/^$/d' > "$INFO/release-$s.txt"
    sed -e '/^$/d' "$INFO/$s.txt" > "$INFO/reconstruido-$s.txt"
    if diff -u "$INFO/release-$s.txt" "$INFO/reconstruido-$s.txt"; then
        vf_log "OK   -$s igual que la release"
    else
        vf_log "ROJO -$s distinto de la release"; fallos=$((fallos + 1))
    fi
done
[ "$fallos" -eq 0 ] || vf_die "la reconstruccion no coincide con la release en $fallos lista(s)"
