#!/bin/bash
# [veation] Llena .cache/downloads con el arbol de cada etapa sacado de las fuentes VERIFICADAS.
#
# Frente a BtbN: ya no clona el HEAD de cada biblioteca. Cada etapa llama a vf_extraer
# (util/dl_functions.sh), que saca su arbol de $VF_FUENTES (montado en /fuentes, solo lectura) tras
# comprobar su sha256 contra fuentes/MANIFIESTO.tsv. El contenedor corre con --network=none: si a una
# etapa le falta su archivo, la descarga FALLA en vez de ir a buscarlo (FFMPEG-PROPIO.md, 2.5.6).
set -xe
cd "$(dirname "$0")"
source util/vars.sh dl only

: "${VF_FUENTES:?VF_FUENTES tiene que apuntar a la carpeta de fuentes verificadas (salida de tools/archivar.sh)}"
VF_FUENTES="$(cd "$VF_FUENTES" && pwd)"
[[ -f "$VF_FUENTES/MANIFIESTO.tsv" ]] || { echo "falta $VF_FUENTES/MANIFIESTO.tsv" >&2; exit 1; }

if docker info -f "{{println .SecurityOptions}}" | grep rootless >/dev/null 2>&1; then
    UIDARGS=()
else
    UIDARGS=( -u "$(id -u):$(id -g)" )
fi

[[ -t 1 ]] && TTY_ARG="-t" || TTY_ARG=""

DL_SCRIPT_DIR="$(mktemp -d)"
trap "rm -rf -- '$DL_SCRIPT_DIR'" EXIT

mkdir -p "${PWD}"/.cache/downloads

for STAGE in scripts.d/*.sh scripts.d/*/*.sh; do
	[[ -f "$STAGE" ]] || continue
	STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"

	cat <<-EOF >"${DL_SCRIPT_DIR}/${STAGENAME}.sh"
		set -xe -o pipefail
		shopt -s dotglob

		source /dl_functions.sh
		source "/$STAGE"
		STG="\$(ffbuild_dockerdl)"

		if [[ -z "\$STG" ]]; then
			exit 0
		fi

		DLHASH="\$(sha256sum <<<"\$STG" | cut -d" " -f1)"
		DLNAME="$STAGENAME"

		if [[ "$1" == "hashonly" ]]; then
			echo "\$DLHASH"
			exit 0
		fi

		TGT="/dldir/\${DLNAME}_\${DLHASH}.tar.xz"
		if [[ -f "\$TGT" ]]; then
			rm -f "/dldir/\${DLNAME}.tar.xz"
			ln -s "\${DLNAME}_\${DLHASH}.tar.xz" "/dldir/\${DLNAME}.tar.xz"
			exit 0
		fi

		WORKDIR="\$(mktemp -d)"
		trap "rm -rf -- '\$WORKDIR'" EXIT
		cd "\$WORKDIR"

		eval "set -e; \$STG"

		tar -I "xz -T0" -cpf "\$TGT.tmp" .
		mv "\$TGT.tmp" "\$TGT"
		rm -f "/dldir/\${DLNAME}.tar.xz"
		ln -s "\${DLNAME}_\${DLHASH}.tar.xz" "/dldir/\${DLNAME}.tar.xz"
	EOF
done

docker run -i $TTY_ARG --rm --network=none "${UIDARGS[@]}" \
	-v "${DL_SCRIPT_DIR}":/stages -v "${PWD}/.cache/downloads":/dldir -v "${PWD}/scripts.d":/scripts.d \
	-v "${PWD}/util/dl_functions.sh":/dl_functions.sh -v "${VF_FUENTES}":/fuentes:ro \
	"${REGISTRY}/${REPO}/base:latest${DOCKER_TAG_SUFFIX:-}" \
	bash -c 'set -xe && for STAGE in /stages/*.sh; do bash $STAGE; done'
