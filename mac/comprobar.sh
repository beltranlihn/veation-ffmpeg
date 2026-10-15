#!/usr/bin/env bash
# mac/comprobar.sh - puertas estaticas de un binario del Mac (FFMPEG-PROPIO.md, 2.5.4 y 5.6 G).
#
#   mac/comprobar.sh <dir> <arquitecturas esperadas>     p. ej. «out/mac-arm64 arm64» o «out/mac-universal "x86_64 arm64"»
#
# Falla si, para ffmpeg y ffprobe:
#   - otool -L lista algo fuera de /usr/lib y /System (Homebrew, /usr/local, una .dylib propia);
#   - alguna arquitectura no tiene minos = macos-min de piezas.conf (vtool -show-build);
#   - lipo -archs no es exactamente la lista esperada;
#   - la firma no verifica (codesign --verify --strict);
#   - en la arquitectura NATIVA de este Mac: -buildconf normalizado != expected/buildconf-mac-<arch>.txt.
# La otra arquitectura de un universal no se ejecuta aqui: mac/universal.sh demuestra que cada rodaja es
# byte a byte el binario fino que ya paso estas puertas en su propio runner.

. "$(dirname "$0")/entorno.sh"

DIR="${1:?uso: mac/comprobar.sh <dir> <arquitecturas>}"
ARCHS="${2:?falta la lista de arquitecturas}"
fallos=0
rojo() { vf_log "ROJO: $*"; fallos=$((fallos + 1)); }

for b in ffmpeg ffprobe; do
    f="$DIR/$b"
    [ -x "$f" ] || { rojo "$b no existe o no es ejecutable"; continue; }

    # Solo las lineas sangradas son bibliotecas. En un universal, otool -L escribe una cabecera por
    # arquitectura («<ruta> (architecture arm64):»); saltar solo la primera linea dejaba la segunda
    # cabecera como si fuera una biblioteca fuera del sistema (mac-universal de la build 38730882310).
    fuera="$(otool -L "$f" | awk '/^[[:space:]]/ { print $1 }' | grep -v -E '^(/usr/lib/|/System/)' || true)"
    [ -z "$fuera" ] || rojo "$b enlaza fuera del sistema: $(echo $fuera)"

    reales="$(lipo -archs "$f")"
    [ "$(echo $reales | tr ' ' '\n' | sort | tr '\n' ' ')" = "$(echo $ARCHS | tr ' ' '\n' | sort | tr '\n' ' ')" ] \
        || rojo "$b tiene arquitecturas «${reales}» y se esperaba «${ARCHS}»"

    for a in $reales; do
        minos="$(vtool -arch "$a" -show-build "$f" | awk '$1 == "minos" { print $2 }' | sort -u)"
        [ "$minos" = "$MACOS_MIN" ] || rojo "$b ($a): minos «${minos}», se pide $MACOS_MIN"
    done

    codesign --verify --strict --verbose=2 "$f" || rojo "$b: la firma no verifica"
done

# -buildconf en la arquitectura nativa
if echo " $ARCHS " | grep -q " $VF_ARCH "; then
    # El mismo volcado (y la misma normalizacion) que leen puertas.mjs y manifiesto.mjs: tenerla
    # copiada aqui dejo pasar a esta puerta la linea «Exiting with exit code 0» de FFmpeg 8.
    info="$(mktemp -d)"
    "$VF_RAIZ/tools/info-binario.sh" "$DIR/ffmpeg" "$info"
    if ! diff -u "$VF_RAIZ/expected/buildconf-$VF_SISTEMA.txt" "$info/buildconf.txt"; then
        rojo "-buildconf de $VF_SISTEMA no es el de expected/buildconf-$VF_SISTEMA.txt"
    fi
    linea="$(sed -n 1p "$info/version.txt")"
    rm -rf "$info"
    [ "$(printf '%s\n' "$linea" | awk '{ print $1, $2, $3 }')" = "ffmpeg version $(vf_version)" ] \
        || rojo "-version dice «${linea}»; se espera «ffmpeg version $(vf_version)»"
fi

[ "$fallos" -eq 0 ] || vf_die "$fallos puerta(s) en rojo en $DIR"
vf_log "puertas del Mac en verde: $DIR ($ARCHS)"
