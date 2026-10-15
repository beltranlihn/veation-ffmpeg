#!/usr/bin/env bash
# tools/verificar-win.sh - puertas estaticas del binario de Windows en el runner Linux
# (FFMPEG-PROPIO.md, 2.5.2). Ejecuta ffmpeg.exe con el wine de la imagen base-win64 (la que dejo
# win/makeimage.sh en el docker local) y despues mide con Node:
#   - tools/puertas.mjs: version, licencia, -buildconf exacto, lista blanca exacta de codificadores,
#     prohibidos ausentes, hwaccels, cadena del driver NVENC minimo, avisos de configure;
#   - tools/pe-imports.mjs: importaciones de ffmpeg.exe y ffprobe.exe solo del sistema y NINGUNA
#     estatica de Media Foundation; y su CONTROL ROJO: un exe de prueba que si importa mfplat.dll tiene
#     que salir rojo (si saliera verde, la puerta no mide nada);
#   - tools/enlazado.mjs: lo que el enlazador abrio de verdad.
#
#   tools/verificar-win.sh <dir con ffmpeg.exe, ffprobe.exe, configure.out, enlazado.log>
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$(cd "${1:?uso: verificar-win.sh <dir>}" && pwd)"

IMAGEN="$(cd "$RAIZ/win" && source util/vars.sh win64 gpl 8.1 && echo "$TARGET_IMAGE")"
docker image inspect "$IMAGEN" >/dev/null || { echo "no esta la imagen $IMAGEN (ejecutar antes win/makeimage.sh)" >&2; exit 1; }

# Prefijo de wine propio, fuera de out/ (que se sube como artefacto) y compartido por todos los
# contenedores: se crea una vez, aqui y a la vista. En la primera build cada contenedor intentaba
# crearlo en HOME=/tmp y wine se negaba («'/tmp' is not owned by you, refusing to create a configuration
# directory there»: /tmp es de root); con 2>/dev/null solo quedaba un version.txt vacio y un «exit 1».
WP="$(mktemp -d)"
trap 'rm -rf "$WP"' EXIT
en_imagen() {
    docker run --rm --network=none -u "$(id -u):$(id -g)" -e HOME=/tmp -e WINEPREFIX=/wp -e WINEDEBUG=-all \
        -v "$RAIZ":/w -v "$DIR":/d -v "$WP":/wp -w /w "$IMAGEN" "$@"
}

fallos=0
echo "wine: $(en_imagen wine --version)"
# (wineserver no esta en el PATH del wine de Ubuntu: se espera a que termine como en win/generate.sh)
if ! en_imagen bash -c 'WINEDEBUG=err+all wineboot --init; rc=$?; while pgrep -x wineserver >/dev/null; do sleep 1; done; exit $rc' > "$DIR/wineboot.log" 2>&1 \
    || [ ! -f "$WP/system.reg" ]; then
    cat "$DIR/wineboot.log" >&2
    echo "ROJO: wine no crea su prefijo con el usuario $(id -u):$(id -g) (sin wine no hay puertas estaticas)" >&2
    exit 1
fi
# Volcado (wine)
en_imagen bash tools/info-binario.sh /d/ffmpeg.exe /d/info --ejecutor wine
en_imagen bash -c 'wine /d/ffprobe.exe -hide_banner -version 2>/dev/null | tr -d "\r" | head -1' > "$DIR/ffprobe-version.txt"
echo "ffprobe: $(cat "$DIR/ffprobe-version.txt")"
grep -q "^ffprobe version $(cd "$RAIZ" && tools/lock.sh get ffmpeg ref)-" "$DIR/ffprobe-version.txt" || { echo "ROJO ffprobe -version" >&2; fallos=$((fallos + 1)); }

node "$RAIZ/tools/puertas.mjs" --sistema win --info "$DIR/info" --binario "$DIR/ffmpeg.exe" \
    --configure-out "$DIR/configure.out" --json "$DIR/puertas-estaticas.json" || fallos=$((fallos + 1))

for exe in ffmpeg.exe ffprobe.exe; do
    node "$RAIZ/tools/pe-imports.mjs" "$DIR/$exe" --prohibir mfplat.dll,mf.dll,mfreadwrite.dll,evr.dll \
        --lista-sistema "$RAIZ/expected/dll-sistema.txt" || fallos=$((fallos + 1))
done

# Control rojo de la puerta de importaciones
tmp="$(mktemp -d)"
cat > "$tmp/hola-mfplat.c" <<'EOF'
#include <windows.h>
#include <mfapi.h>
int main(void) { return (int)MFStartup(MF_VERSION, MFSTARTUP_FULL); }
EOF
docker run --rm --network=none -u "$(id -u):$(id -g)" -v "$tmp":/t -w /t "$IMAGEN" \
    bash -c 'x86_64-w64-mingw32-gcc hola-mfplat.c -o hola-mfplat.exe -lmfplat'
if node "$RAIZ/tools/pe-imports.mjs" "$tmp/hola-mfplat.exe" --prohibir mfplat.dll >/dev/null; then
    echo "ROJO: el control (un exe que importa mfplat.dll) paso la puerta: la puerta no mide" >&2
    fallos=$((fallos + 1))
else
    echo "OK control rojo: la puerta de importaciones caza un exe que importa mfplat.dll"
fi
rm -rf "$tmp"

node "$RAIZ/tools/enlazado.mjs" --sistema win --log "$DIR/enlazado.log" --salida "$DIR/linked-win.txt" \
    --json "$DIR/enlazado.json" || fallos=$((fallos + 1))

[ "$fallos" -eq 0 ] || { echo "verificar-win: $fallos bloque(s) en rojo" >&2; exit 1; }
echo "verificar-win: todo en verde"
