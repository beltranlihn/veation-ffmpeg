#!/usr/bin/env bash
# tools/modificaciones.sh - toda orden de los scripts que modifica un arbol de terceros tiene que estar
# inventariada, letra por letra, en patches/MODIFICACIONES.md (FFMPEG-PROPIO.md, 3.7).
#
#   tools/modificaciones.sh
#
# Busca en win/scripts.d y mac/ las lineas con sed -i, perl -pi, patch -p, git apply, «>> ...pc» o
# «> ....tmp» (reescritura de un archivo). Falla si una no esta dentro de un bloque ``` del inventario,
# y si un bloque del inventario ya no aparece en ningun script.
. "$(dirname "$0")/lib.sh"

INV="$VF_RAIZ/patches/MODIFICACIONES.md"
bloques="$(awk '/^```/ { d = !d; next } d { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); if ($0 != "") print }' "$INV")"
fallos=0

encontradas="$(cd "$VF_RAIZ" && grep -n -E '(sed -i|sed -E .*> "\$pc\.tmp"|perl -p?i|patch -p|git apply|>> .*\.pc|> [^ ]*\.tmp)' \
    win/scripts.d/*.sh mac/*.sh mac/deps/*.sh 2>/dev/null | grep -v -E ':[0-9]+:[[:space:]]*#' || true)"

while IFS= read -r linea; do
    [ -n "$linea" ] || continue
    archivo="${linea%%:*}"; resto="${linea#*:}"; num="${resto%%:*}"; orden="${resto#*:}"
    orden="$(printf '%s' "$orden" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if ! printf '%s\n' "$bloques" | grep -qxF -- "$orden"; then
        vf_log "ROJO: $archivo:$num modifica un arbol y no esta en patches/MODIFICACIONES.md:"
        vf_log "      $orden"
        fallos=$((fallos + 1))
    fi
done <<EOF
$encontradas
EOF

while IFS= read -r b; do
    [ -n "$b" ] || continue
    if ! (cd "$VF_RAIZ" && grep -rqF -- "$b" win/scripts.d mac); then
        vf_log "ROJO: el inventario lista una orden que ya no esta en ningun script:"
        vf_log "      $b"
        fallos=$((fallos + 1))
    fi
done <<EOF
$bloques
EOF

# Los parches de patches/<pieza>/ (no los de reserva/) llevan la marca en su primera linea.
for p in "$VF_RAIZ"/patches/*/*.patch; do
    [ -f "$p" ] || continue
    case "$p" in */reserva/*) continue ;; esac
    head -1 "$p" | grep -q '^Modified by Alma Digital Studio, [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}:' \
        || { vf_log "ROJO: $(basename "$p") no empieza por «Modified by Alma Digital Studio, AAAA-MM-DD:»"; fallos=$((fallos + 1)); }
done

[ "$fallos" -eq 0 ] || vf_die "modificaciones sin inventariar: $fallos"
vf_log "modificaciones: todas inventariadas"
