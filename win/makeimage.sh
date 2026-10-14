#!/bin/bash
# [veation] Construye las tres imagenes (base, base-win64 con la toolchain, win64-gpl-8.1 con las
# bibliotecas) SOLO en el docker local del runner. Cambios frente a BtbN:
#   - nada se publica en ghcr (FFMPEG-PROPIO.md, 2.7): las imagenes llevan binarios GPL;
#   - cache de buildx: VF_CACHE=gha (cache de Actions, no descargable publicamente) o VF_CACHE=none
#     (una release se compila siempre en frio); en local, VF_CACHE=local usa .cache/ como BtbN;
#   - la imagen base se fija por digest y sus herramientas por sha256 (versions.lock);
#   - la toolchain: crosstool-ng sale de su archivo en fuentes/toolchain-win (CTNG_ARCHIVO) y se
#     compila con los tarballs de esa misma carpeta, sin red (RUN --network=none) y sin permiso para
#     descargar nada (ct-ng-config: CT_FORBID_DOWNLOAD);
#   - las etapas de bibliotecas compilan sin red (util/vars.sh).
set -xeo pipefail
cd "$(dirname "$0")"
source util/vars.sh

: "${VF_FUENTES:?VF_FUENTES tiene que apuntar a la carpeta de fuentes verificadas}"
VF_FUENTES="$(cd "$VF_FUENTES" && pwd)"
VF_RAIZ="$(cd .. && pwd)"
VF_CACHE="${VF_CACHE:-local}"
LOCK="$VF_RAIZ/tools/lock.sh"

docker buildx inspect ffbuilder &>/dev/null || docker buildx create \
    --bootstrap \
    --name ffbuilder \
    --buildkitd-flags "--oci-max-parallelism=4" \
    --driver-opt network=host \
    --driver-opt env.BUILDKIT_STEP_LOG_MAX_SIZE=-1 \
    --driver-opt env.BUILDKIT_STEP_LOG_MAX_SPEED=-1

if [[ -z "$NOCLEAN" ]]; then
    trap 'rc=$?; [[ $rc -eq 0 ]] && docker buildx rm -f ffbuilder; exit $rc' EXIT
fi

GH_REPO="${REGISTRY}/${REPO}"
BAKE_TARGETS=( image )

if [[ -z "$QUICKBUILD" ]]; then
    BAKE_TARGETS+=( target-base )
fi

UBUNTU_REF="$("$LOCK" get ubuntu-base origen)@$("$LOCK" get ubuntu-base digest)"
UBUNTU_REF="${UBUNTU_REF#docker.io/library/}"

to_bake() {
    printf "$@"
    echo
}

# cache_lines <nombre>: lineas cache-from/cache-to segun VF_CACHE
cache_lines() {
    local nombre="${1//[:\/]/_}"
    case "$VF_CACHE" in
        gha)
            to_bake '  cache-from = ["type=gha,scope=vf-%s"]' "$nombre"
            to_bake '  cache-to   = ["type=gha,mode=max,scope=vf-%s"]' "$nombre"
            ;;
        local)
            to_bake '  cache-from = ["type=local,src=.cache/%s"]' "$nombre"
            to_bake '  cache-to   = ["type=local,mode=max,compression=zstd,compression-level=1,dest=.cache/%s"]' "$nombre"
            ;;
        none)
            to_bake '  no-cache   = true'
            ;;
        *) echo "VF_CACHE desconocido: $VF_CACHE" >&2; exit 1 ;;
    esac
}

bake_images() {
    local -; set +x
    {
        if [[ -z "$QUICKBUILD" ]]; then
            to_bake 'target "base" {'
            to_bake '  context    = "images/base"'
            to_bake '  tags       = ["%s"]' "$BASE_IMAGE"
            to_bake '  output     = ["type=docker"]'
            to_bake '  args       = {'
            to_bake '    UBUNTU_REF          = "%s"' "$UBUNTU_REF"
            to_bake '    AUTOCONF_DEB_URL    = "%s"' "$("$LOCK" get autoconf-deb origen)"
            to_bake '    AUTOCONF_DEB_SHA256 = "%s"' "$("$LOCK" get autoconf-deb sha256)"
            to_bake '    CMAKE_URL           = "%s"' "$("$LOCK" get cmake-linux origen)"
            to_bake '    CMAKE_SHA256        = "%s"' "$("$LOCK" get cmake-linux sha256)"
            to_bake '    MESON_URL           = "%s"' "$("$LOCK" get meson origen)"
            to_bake '    MESON_SHA256        = "%s"' "$("$LOCK" get meson sha256)"
            to_bake '  }'
            cache_lines "$BASE_IMAGE"
            to_bake '}'

            to_bake 'target "target-base" {'
            to_bake '  context    = "images/base-%s"' "$TARGET"
            to_bake '  args       = { GH_REPO = "%s", CTNG_COMMIT = "%s", CTNG_ARCHIVO = "%s" }' "$GH_REPO" "$("$LOCK" get crosstool-ng commit)" "$(basename "$("$LOCK" archivo crosstool-ng)")"
            to_bake '  contexts   = { "%s/base" = "target:base", "vf-toolchain" = "%s" }' "$GH_REPO" "$VF_FUENTES/toolchain-win"
            to_bake '  tags       = ["%s"]' "$TARGET_IMAGE"
            to_bake '  output     = ["type=docker"]'
            cache_lines "$TARGET_IMAGE"
            to_bake '}'
        fi

        to_bake 'target "image" {'
        to_bake '  context    = "."'
        if [[ -z "$QUICKBUILD" ]]; then
            to_bake '  contexts   = { "%s/base-%s" = "target:target-base" }' "$GH_REPO" "$TARGET"
        fi
        to_bake '  tags       = ["%s"]' "$IMAGE"
        to_bake '  output     = ["type=docker"]'
        cache_lines "$IMAGE"
        to_bake '}'
    } | tee /dev/stderr | docker buildx --builder ffbuilder bake -f - "$@"
}

if [[ -z "$QUICKBUILD" ]]; then
    bake_images base
fi

./download.sh
./generate.sh "$TARGET" "$VARIANT" "${ADDINS[@]}"

bake_images "${BAKE_TARGETS[@]}"
