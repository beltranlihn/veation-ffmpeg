#!/usr/bin/env bash
# mac/deps.sh - compila las bibliotecas del Mac, todas estaticas en /tmp/vf/prefix, SIN red, desde las
# fuentes verificadas (FFMPEG-PROPIO.md, 2.5.4). Cada pieza tiene su script en mac/deps/NN-<pieza>.sh,
# que define PIEZA y la funcion construir(); este archivo extrae el arbol (vf_extraer: identidad del
# lock + sha256 del manifiesto) y la ejecuta dentro de el.
#
#   mac/deps.sh --fuentes <dir> [--solo <pieza>]

. "$(dirname "$0")/entorno.sh"

FUENTES=""; SOLO=""
while [ $# -gt 0 ]; do
    case "$1" in
        --fuentes) FUENTES="$2"; shift 2 ;;
        --solo)    SOLO="$2"; shift 2 ;;
        *) vf_die "opcion desconocida: $1" ;;
    esac
done
[ -n "$FUENTES" ] || vf_die "falta --fuentes <dir>"
FUENTES="$(cd "$FUENTES" && pwd)"

if [ -z "$SOLO" ]; then
    rm -rf "$PREFIX"
fi
mkdir -p "$PREFIX/lib/pkgconfig" "$PREFIX/include" "$VF_TRABAJO"

n=0
for script in "$VF_RAIZ"/mac/deps/[0-9][0-9]-*.sh; do
    PIEZA=""
    . "$script"
    [ -n "$PIEZA" ] || vf_die "$script no define PIEZA"
    if [ -n "$SOLO" ] && [ "$PIEZA" != "$SOLO" ]; then continue; fi
    case ",$(vf_lock_campo "$PIEZA" sistemas)," in *,mac,*) ;; *) vf_die "$script: «$PIEZA» no es una pieza del Mac en el lock" ;; esac
    vf_log "=== $PIEZA ($(vf_lock_campo "$PIEZA" ref))"
    dir="$VF_TRABAJO/$PIEZA"
    vf_extraer "$FUENTES" "$PIEZA" "$dir"
    (cd "$dir" && set -x && construir)
    rm -rf "$dir"
    n=$((n + 1))
done
[ "$n" -gt 0 ] || vf_die "no se compilo ninguna pieza (¿--solo $SOLO?)"

# Solo bibliotecas estaticas: una .dylib en el prefijo haria que el enlazador la prefiriese.
if find "$PREFIX" -name '*.dylib' | grep -q .; then
    find "$PREFIX" -name '*.dylib' >&2
    vf_die "hay .dylib en $PREFIX: todo tiene que ser estatico"
fi

# Cada objeto de cada .a con el minimo de macOS del lock (un objeto con minos mayor se notaria al
# enlazar como «was built for newer 'macOS' version», que mac/ffmpeg.sh vigila; aqui se mira antes y
# por biblioteca).
for a in "$PREFIX"/lib/*.a; do
    malos="$(otool -l "$a" 2>/dev/null | awk '/cmd LC_BUILD_VERSION/ { b = 1 } b && /minos/ { print $2; b = 0 }' | sort -u | grep -v -x "$MACOS_MIN" || true)"
    [ -z "$malos" ] || vf_die "$(basename "$a") tiene objetos con minos $malos (se pide $MACOS_MIN)"
done
vf_log "bibliotecas del Mac listas en $PREFIX ($n pieza(s))"
