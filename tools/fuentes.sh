#!/usr/bin/env bash
# tools/fuentes.sh - arma el paquete de fuente completo y correspondiente (FFMPEG-PROPIO.md, 4.2).
#
#   tools/fuentes.sh <dir fuentes> <dir build> <dir avisos> <dir salida>
#
#   <dir fuentes>  salida de tools/archivar.sh (ffmpeg/, bibliotecas/, toolchain-win/, MANIFIESTO.tsv)
#   <dir build>    BUILDINFO-*.txt, linked-*.txt y configure-*.args de los jobs de compilacion
#   <dir avisos>   salida de «avisos.mjs textos» (licencias/<pieza>/...)
#
# Contenido de veation-ffmpeg-<version>-source.tar.xz:
#   README-SOURCE.md   que hay y como reconstruir, paso a paso
#   receta/            git archive del repositorio en el commit de la release (win/ = fork de BtbN, mac/,
#                      tools/, piezas.conf, versions.lock, patches/, notices/, .github/workflows/)
#   ffmpeg/ bibliotecas/ toolchain-win/ MANIFIESTO.tsv   tal cual salen de archivar.sh (la carpeta
#                      raiz del paquete sirve directamente como VF_FUENTES para reconstruir)
#   build/             BUILDINFO-*.txt, linked-*.txt, configure-*.args
#   licencias/         COPYING, NOTICE y PATENTS de cada pieza, extraidos de su fuente
# Solo van las piezas del lock (nunca las descargas de piezas excluidas). Tar determinista; si pasa de
# 2 GiB (limite de un asset de GitHub) se parte en .part00, .part01... Imprime en la ultima linea
# «sha256 <archivo entero>».
. "$(dirname "$0")/lib.sh"

FUENTES="$(cd "${1:?dir fuentes}" && pwd)"; BUILD="$(cd "${2:?dir build}" && pwd)"
AVISOS="$(cd "${3:?dir avisos}" && pwd)"; SALIDA="${4:?dir salida}"
mkdir -p "$SALIDA"; SALIDA="$(cd "$SALIDA" && pwd)"
tar --version | grep -q 'GNU tar' || vf_die "fuentes.sh necesita GNU tar"
"$VF_RAIZ/tools/fuentes-comprobar.sh" "$FUENTES"

VERSION="$(vf_version)"
NOMBRE="veation-ffmpeg-$VERSION-source"
COMMIT="$(git -C "$VF_RAIZ" rev-parse HEAD)"
EPOCH="$(git -C "$VF_RAIZ" log -1 --format=%ct HEAD)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/$NOMBRE"
mkdir -p "$P/receta" "$P/build" "$P/licencias"

git -C "$VF_RAIZ" archive --format=tar HEAD | tar -xf - -C "$P/receta"
cp -R "$FUENTES/ffmpeg" "$FUENTES/bibliotecas" "$P/"
[ -d "$FUENTES/toolchain-win" ] && cp -R "$FUENTES/toolchain-win" "$P/"
cp "$FUENTES/MANIFIESTO.tsv" "$P/"
for f in "$BUILD"/BUILDINFO-*.txt "$BUILD"/linked-*.txt "$BUILD"/configure-*.args; do [ -f "$f" ] && cp "$f" "$P/build/"; done
cp -R "$AVISOS/licencias/." "$P/licencias/"

cat > "$P/README-SOURCE.md" <<EOF
# Fuente completo de FFmpeg $VERSION (veation-ffmpeg)

Fuente completo y correspondiente de los binarios de FFmpeg $VERSION que Alma Digital Studio
distribuye con VEATION (Windows x64 y macOS universal), segun la GNU GPL version 3, seccion 6.
Receta: https://github.com/${GITHUB_REPOSITORY:-beltranlihn/veation-ffmpeg}, commit $COMMIT.

## Contenido

| Carpeta | Que es |
|---|---|
| \`receta/\` | la receta completa en el commit de la release: \`win/\` (fork de BtbN/FFmpeg-Builds), \`mac/\`, \`tools/\`, \`versions.lock\`, \`piezas.conf\`, \`patches/\`, \`notices/\`, \`.github/workflows/\` |
| \`ffmpeg/\` | \`ffmpeg-$(vf_lock_campo ffmpeg ref).tar.xz\` y su firma \`.asc\`, tal como los publica ffmpeg.org |
| \`bibliotecas/\` | el arbol exacto de cada biblioteca enlazada (o su tarball oficial), uno por pieza |
| \`toolchain-win/\` | GCC, binutils, mingw-w64 (CRT y winpthreads se enlazan), crosstool-ng y sus dependencias |
| \`MANIFIESTO.tsv\` | pieza, version, origen, commit o sha256 de origen, archivo, sha256 del archivo, licencia, sistemas |
| \`build/\` | BUILDINFO de cada binario (-buildconf, -encoders, toolchain, runner), linea de configure y lo que abrio el enlazador |
| \`licencias/\` | los textos de licencia y avisos de cada pieza, sacados de su fuente |

## Reconstruir

La carpeta raiz de este paquete sirve tal cual como carpeta de fuentes (\`VF_FUENTES\`).

**macOS** (Xcode $(vf_lock_campo xcode ref), un Mac Apple Silicon para arm64 y uno Intel para x86_64):

    cd receta
    mac/herramientas.sh                                   # CMake, meson, ninja, pkgconf, autotools, nasm (sha256 del lock)
    mac/construir.sh --fuentes .. --salida ../salida-\$(uname -m)
    mac/universal.sh ../salida-arm64 ../salida-x86_64 ../salida-universal   # con las dos salidas en el mismo Mac

**Windows** (se compila en Linux x86_64 con Docker y buildx; la toolchain sale de toolchain-win/):

    cd receta
    VF_FUENTES=\$PWD/.. VF_CACHE=none win/makeimage.sh win64 gpl 8.1
    VF_FUENTES=\$PWD/.. VF_SALIDA=\$PWD/../salida-win win/build.sh win64 gpl 8.1

Despues, \`tools/info-binario.sh\` y \`tools/puertas.mjs\` comparan el resultado con \`build/BUILDINFO-*.txt\`.
El workflow \`.github/workflows/verificar-fuente.yml\` hace exactamente esto en GitHub Actions.

## Modificaciones

FFmpeg se compila sin modificar. Las unicas modificaciones a fuentes de terceros estan en
\`receta/patches/MODIFICACIONES.md\`, con su fecha.
EOF

# tar determinista
( cd "$TMP" && find "$NOMBRE" -print0 | LC_ALL=C sort -z | tar --null --no-recursion -T - --format=gnu \
    --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' -cf - ) \
    | xz -T1 -6 -c > "$SALIDA/$NOMBRE.tar.xz"
SHA="$(vf_sha256 "$SALIDA/$NOMBRE.tar.xz")"
TAM="$(wc -c < "$SALIDA/$NOMBRE.tar.xz" | tr -d ' ')"
LIMITE=$((2000 * 1024 * 1024))
if [ "$TAM" -gt "$LIMITE" ]; then
    ( cd "$SALIDA" && split -b "$LIMITE" -d -a 2 "$NOMBRE.tar.xz" "$NOMBRE.tar.xz.part" && rm "$NOMBRE.tar.xz" )
    vf_log "paquete de fuente partido en $(ls "$SALIDA" | grep -c "$NOMBRE.tar.xz.part") partes ($TAM bytes)"
else
    vf_log "paquete de fuente: $NOMBRE.tar.xz ($TAM bytes)"
fi
echo "sha256 $SHA"
