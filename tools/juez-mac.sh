#!/usr/bin/env bash
# tools/juez-mac.sh - instala el juez del Mac (FFmpeg de Homebrew, solo para comparar: nunca se
# distribuye) y deja su ruta en JUEZ (en $GITHUB_ENV si existe; si no, la imprime).
#
# El juez tiene que ser de la MISMA rama de FFmpeg que el candidato (la del lock, 8.1): la formula
# «ffmpeg» de Homebrew ya es 9.0.x, y un juez de otra version no decodifica igual por razones que no son
# de esta receta (build 38728167219: el AAC que fabrica el 9.0.1 lo decodifica el 9.0.1 en 24000
# muestras, recortando el relleno final, y el 8.1.3 en 24576, sin recortarlo; identicas en el tramo
# comun). En Windows el juez es el 8.1 de gyan, de la misma rama. Homebrew mantiene la rama 8 en la
# formula versionada «ffmpeg@8» (keg-only), con bottle para Apple Silicon.
. "$(dirname "$0")/lib.sh"

FORMULA=ffmpeg@8
RAMA="$(vf_lock_campo ffmpeg ref | cut -d. -f1,2)"
brew install "$FORMULA" >&2
J="$(brew --prefix "$FORMULA")/bin/ffmpeg"
[ -x "$J" ] || vf_die "no esta $J tras instalar $FORMULA"
v="$("$J" -hide_banner -version | sed -n 1p)"
case "$v" in
    "ffmpeg version $RAMA."*|"ffmpeg version $RAMA") ;;
    *) vf_die "el juez dice «${v}» y el candidato es FFmpeg $RAMA: un juez de otra rama no sirve para la puerta F" ;;
esac
vf_log "juez: $J ($v)"
if [ -n "${GITHUB_ENV:-}" ]; then echo "JUEZ=$J" >> "$GITHUB_ENV"; else echo "$J"; fi
