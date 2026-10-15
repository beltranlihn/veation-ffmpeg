#!/bin/bash
# [veation] Ninguna etapa clona ni descarga nada. Cada una extrae su arbol de las fuentes VERIFICADAS
# (tools/fetch.sh + tools/archivar.sh -> fuentes/, montado en /fuentes por download.sh), que son
# exactamente las que van al paquete de fuente. La cadena que devuelve ffbuild_dockerdl lleva la
# identidad de la pieza (commit o sha256 del lock), asi que un cambio de version cambia la cache.

default_dl() {
    echo "vf_extraer \"$SCRIPT_PIEZA\" \"$1\" \"${SCRIPT_COMMIT:-$SCRIPT_SHA256}\""
}

ffbuild_dockerdl() {
    default_dl .
}

# vf_extraer <pieza> <destino> <identidad>
# Lo ejecuta download.sh dentro del contenedor base, con --network=none. Falla si la pieza no esta en
# fuentes/MANIFIESTO.tsv, si su identidad no es la del script (aplicar-lock.sh desfasado), si falta
# el archivo o si su sha256 no es el del manifiesto.
vf_extraer() {
    local pieza="$1" destino="$2" id="$3" fila archivo sha
    fila="$(awk -F'\t' -v p="$pieza" '$1 == p' /fuentes/MANIFIESTO.tsv)"
    if [[ -z "$fila" ]]; then
        echo "vf_extraer: «${pieza}» no esta en fuentes/MANIFIESTO.tsv" >&2
        return 1
    fi
    if [[ "$(cut -f5 <<<"$fila")" != "$id" ]]; then
        echo "vf_extraer: la identidad de «${pieza}» en el script ($id) no es la de las fuentes ($(cut -f5 <<<"$fila")); ejecutar tools/aplicar-lock.sh" >&2
        return 1
    fi
    archivo="/fuentes/$(cut -f6 <<<"$fila")"
    sha="$(cut -f7 <<<"$fila")"
    if [[ ! -f "$archivo" ]]; then
        echo "vf_extraer: falta $archivo" >&2
        return 1
    fi
    echo "$sha  $archivo" | sha256sum -c - >&2
    mkdir -p "$destino"
    tar -xf "$archivo" -C "$destino" --strip-components=1 --no-same-owner
}

