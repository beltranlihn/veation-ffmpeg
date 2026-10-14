#!/usr/bin/env bash
# tools/fuentes-comprobar.sh - comprueba una carpeta de fuentes (salida de archivar.sh, o la carpeta
# del paquete de fuente ya extraido) contra versions.lock, ANTES de compilar nada con ella.
#
#   tools/fuentes-comprobar.sh <dir fuentes> [win|mac]
#
# Falla si: falta MANIFIESTO.tsv; una pieza fuente/toolchain del sistema no tiene fila o archivo; la
# identidad de una fila no es la del lock; el sha256 de un archivo no es el del manifiesto; o el
# manifiesto tiene una pieza que el lock no tiene (algo que no deberia ir al paquete).
. "$(dirname "$0")/lib.sh"

F="$(cd "${1:?uso: fuentes-comprobar.sh <dir> [win|mac]}" && pwd)"
SIS="${2:-}"
M="$F/MANIFIESTO.tsv"
[ -f "$M" ] || vf_die "falta $M"
fallos=0
rojo() { vf_log "ROJO: $*"; fallos=$((fallos + 1)); }

for pieza in $(vf_lock_piezas "$SIS" fuente,toolchain); do
    fila="$(awk -F'\t' -v p="$pieza" 'NR > 1 && $1 == p' "$M")"
    if [ -z "$fila" ]; then rojo "«$pieza» no esta en el manifiesto"; continue; fi
    case "$(vf_lock_campo "$pieza" tipo)" in
        git) esperado="$(vf_lock_campo "$pieza" commit)" ;;
        *)   esperado="$(vf_lock_campo "$pieza" sha256)" ;;
    esac
    id="$(printf '%s\n' "$fila" | cut -f5)"
    rel="$(printf '%s\n' "$fila" | cut -f6)"
    sha="$(printf '%s\n' "$fila" | cut -f7)"
    [ "$id" = "$esperado" ] || rojo "«$pieza»: identidad $id, el lock pide $esperado"
    [ "$rel" = "$(vf_archivo_fuente "$pieza")" ] || rojo "«$pieza»: archivo $rel, se esperaba $(vf_archivo_fuente "$pieza")"
    if [ ! -f "$F/$rel" ]; then rojo "«$pieza»: falta $rel"; continue; fi
    [ "$(vf_sha256 "$F/$rel")" = "$sha" ] || rojo "«$pieza»: el sha256 de $rel no es el del manifiesto"
done
for pieza in $(awk -F'\t' 'NR > 1 { print $1 }' "$M"); do
    vf_lock_campo "$pieza" tipo >/dev/null 2>&1 || rojo "el manifiesto trae «$pieza», que no esta en el lock"
done
[ "$fallos" -eq 0 ] || vf_die "fuentes: $fallos problema(s) en $F"
vf_log "fuentes verificadas en $F${SIS:+ ($SIS)}"
