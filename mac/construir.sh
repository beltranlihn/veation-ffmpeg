#!/usr/bin/env bash
# mac/construir.sh - compilacion completa del Mac para la arquitectura de este runner:
# bibliotecas (mac/deps.sh) + FFmpeg (mac/ffmpeg.sh) + puertas (mac/comprobar.sh).
#
#   mac/construir.sh --fuentes <dir> --salida <dir>
#
# No usa la red: las herramientas ya tienen que estar (mac/herramientas.sh) y todo el fuente sale de
# --fuentes. build.yml y verificar-fuente.yml (este, desde el paquete de fuente) lo ejecutan dentro de
# sandbox-exec sin red.

. "$(dirname "$0")/entorno.sh"

FUENTES=""; SALIDA=""
while [ $# -gt 0 ]; do
    case "$1" in
        --fuentes) FUENTES="$2"; shift 2 ;;
        --salida)  SALIDA="$2"; shift 2 ;;
        *) vf_die "opcion desconocida: $1" ;;
    esac
done
[ -n "$FUENTES" ] && [ -n "$SALIDA" ] || vf_die "uso: mac/construir.sh --fuentes <dir> --salida <dir>"
[ -x "$VF_HERRAMIENTAS/bin/cmake" ] || vf_die "faltan las herramientas: ejecutar antes mac/herramientas.sh"

"$VF_RAIZ/mac/deps.sh" --fuentes "$FUENTES"
"$VF_RAIZ/mac/ffmpeg.sh" --fuentes "$FUENTES" --salida "$SALIDA"
"$VF_RAIZ/mac/comprobar.sh" "$SALIDA" "$VF_ARCH"
