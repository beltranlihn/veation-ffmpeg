#!/bin/bash
# [veation] Compila FFmpeg dentro de la imagen win64-gpl-8.1 (makeimage.sh) a partir del tarball
# VERIFICADO, no de un git clone. Cambios frente a BtbN (detalle en win/VEATION-CAMBIOS.md):
#   - fuente: fuentes/ffmpeg/ffmpeg-8.1.3.tar.xz, con su sha256 del lock comprobado otra vez aqui;
#     desde el tarball, ffbuild/version.sh da «8.1.3» y no «n8.1.3» (FFMPEG-PROPIO.md, 1.1);
#   - configure: EXACTAMENTE la linea de piezas.conf (tools/piezas.sh args win), un argumento por linea;
#     sin --extra-version=$(date) ni --disable-debug (ffmpeg_g.exe conserva simbolos);
#   - sin red dentro del contenedor (--network=none);
#   - tras compilar se REENLAZAN ffmpeg_g.exe y ffprobe_g.exe con -Wl,--trace dos veces (archivos
#     abiertos y miembros de archivo usados): el binario que se
#     publica es el de ese reenlazado, asi que la traza corresponde a el por construccion;
#   - salida en $VF_SALIDA (out/win por defecto), sin zip: lo empaqueta tools/empaquetar.sh.
set -xe
cd "$(dirname "$0")"
source util/vars.sh

source "variants/${TARGET}-${VARIANT}.sh"

for addin in ${ADDINS[*]}; do
    source "addins/${addin}.sh"
done

: "${VF_FUENTES:?VF_FUENTES tiene que apuntar a la carpeta de fuentes verificadas}"
VF_FUENTES="$(cd "$VF_FUENTES" && pwd)"
VF_RAIZ="$(cd .. && pwd)"
VF_SALIDA="${VF_SALIDA:-$VF_RAIZ/out/win}"

TARBALL_REL="$("$VF_RAIZ/tools/lock.sh" archivo ffmpeg)"
TARBALL_SHA="$("$VF_RAIZ/tools/lock.sh" get ffmpeg sha256)"
echo "${TARBALL_SHA}  ${VF_FUENTES}/${TARBALL_REL}" | sha256sum -c -

if docker info -f "{{println .SecurityOptions}}" | grep rootless >/dev/null 2>&1; then
    UIDARGS=()
else
    UIDARGS=( -u "$(id -u):$(id -g)" )
fi

rm -rf ffbuild
mkdir ffbuild
"$VF_RAIZ/tools/piezas.sh" args win > ffbuild/configure.args

BUILD_SCRIPT="$(mktemp)"
trap "rm -f -- '$BUILD_SCRIPT'" EXIT

cat <<'EOF' >"$BUILD_SCRIPT"
    set -xe -o pipefail
    cd /ffbuild
    rm -rf ffmpeg
    mkdir ffmpeg
    tar -xf "/fuentes/$TARBALL_REL" -C ffmpeg --strip-components=1 --no-same-owner
    cd ffmpeg

    ARGS=()
    while IFS= read -r a; do ARGS+=( "$a" ); done < /ffbuild/configure.args
    ./configure "${ARGS[@]}" 2>&1 | tee /ffbuild/configure.out || { cat ffbuild/config.log; exit 1; }
    cp ffbuild/config.log /ffbuild/config.log

    make -j$(nproc) V=1

    # Reenlazado con traza: los objetos ya estan, solo se repite el enlace de los dos programas. La
    # traza (stdout, con bufer) y los avisos del enlazador (stderr) van a archivos distintos: juntos se
    # cortaban a mitad de ruta (visto en el Mac, mac/ffmpeg.sh) y tools/enlazado.mjs perdia archivos.
    LDEXE="$(sed -n 's/^LDEXEFLAGS=//p' ffbuild/config.mak)"
    rm -f ffmpeg_g.exe ffprobe_g.exe ffmpeg.exe ffprobe.exe
    make V=1 LDEXEFLAGS="$LDEXE -Wl,--trace -Wl,--trace" ffmpeg_g.exe ffprobe_g.exe > /ffbuild/enlazado.log 2> /ffbuild/enlazado-avisos.log \
        || { tail -n 100 /ffbuild/enlazado.log /ffbuild/enlazado-avisos.log; exit 1; }
    make V=1 ffmpeg.exe ffprobe.exe

    cp ffmpeg.exe ffprobe.exe ffmpeg_g.exe ffprobe_g.exe COPYING.GPLv3 /ffbuild/
EOF

[[ -t 1 ]] && TTY_ARG="-t" || TTY_ARG=""

docker run --rm -i $TTY_ARG --network=none "${UIDARGS[@]}" -e TARBALL_REL="$TARBALL_REL" \
    -v "$PWD/ffbuild":/ffbuild -v "$VF_FUENTES":/fuentes:ro -v "$BUILD_SCRIPT":/build.sh \
    "$IMAGE" bash /build.sh

mkdir -p "$VF_SALIDA"
for f in ffmpeg.exe ffprobe.exe ffmpeg_g.exe ffprobe_g.exe COPYING.GPLv3 configure.args configure.out config.log enlazado.log enlazado-avisos.log; do
    cp "ffbuild/$f" "$VF_SALIDA/$f"
done
docker image inspect -f '{{.Id}}' "$IMAGE" > "$VF_SALIDA/imagen-id.txt"

rm -rf ffbuild
