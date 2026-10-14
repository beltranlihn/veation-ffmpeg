#!/usr/bin/env bash
# tools/archivar.sh - convierte lo que bajo tools/fetch.sh en «fuentes/»: un archivo por pieza, con el
# mismo nombre y los mismos bytes que iran al paquete de fuente (FFMPEG-PROPIO.md, 2.5.1 y 4.2), y el
# MANIFIESTO.tsv que lo describe. Los dos sistemas compilan SOLO desde aqui: lo que se compila y lo que
# se publica como fuente son, por construccion, lo mismo.
#
#   tools/archivar.sh <dir de fetch.sh> <dir fuentes>
#
# Estructura:
#   ffmpeg/ffmpeg-8.1.3.tar.xz (+ .asc)              el tarball oficial y su firma, tal cual
#   bibliotecas/<archivo>                            rol fuente
#   toolchain-win/<archivo>                          rol toolchain (GCC, binutils, mingw-w64, crosstool-ng...)
#     git     -> <pieza>-<ref>-<commit12>.tar.xz: tar determinista (orden por nombre, fecha = la del commit,
#                propietario 0:0, permisos normalizados) comprimido con xz -T1 (con un solo hilo la salida
#                es la misma en cualquier maquina con la misma version de xz)
#     tarball -> el archivo del proyecto con su nombre y sus bytes
#   MANIFIESTO.tsv   pieza ref tipo origen identidad archivo sha256 rol sistemas spdx
. "$(dirname "$0")/lib.sh"

ORIGEN="$(cd "${1:?uso: archivar.sh <dir fetch> <dir fuentes>}" && pwd)"
DEST="${2:?falta el dir de fuentes}"
mkdir -p "$DEST"; DEST="$(cd "$DEST" && pwd)"
command -v xz >/dev/null || vf_die "falta xz"
tar --version | grep -q 'GNU tar' || vf_die "archivar.sh necesita GNU tar (Linux)"

printf 'pieza\tref\ttipo\torigen\tidentidad\tarchivo\tsha256\trol\tsistemas\tspdx\n' > "$DEST/MANIFIESTO.tsv"

spdx_de() {
    local f="$VF_RAIZ/notices/$1/pieza.conf"
    if [ -f "$f" ]; then awk -F= '$1 == "spdx" { print $2; exit }' "$f"; else echo "-"; fi
}

for pieza in $(vf_lock_piezas "" fuente,toolchain); do
    tipo="$(vf_lock_campo "$pieza" tipo)"
    rel="$(vf_archivo_fuente "$pieza")"
    mkdir -p "$DEST/$(dirname "$rel")"
    case "$tipo" in
        git)
            id="$(vf_lock_campo "$pieza" commit)"
            arbol="$ORIGEN/arbol/$pieza"
            [ -d "$arbol" ] || vf_die "falta $arbol (ejecutar tools/fetch.sh)"
            nombre="$(basename "$rel" .tar.xz)"
            tar --sort=name --format=gnu --mtime="@$(cat "$arbol.epoch")" --owner=0 --group=0 --numeric-owner \
                --mode='u+rwX,go+rX,go-w' --transform="s,^\\.,$nombre," -C "$arbol" -cf - . \
                | xz -T1 -6 -c > "$DEST/$rel.part"
            mv "$DEST/$rel.part" "$DEST/$rel"
            ;;
        tarball)
            id="$(vf_lock_campo "$pieza" sha256)"
            cp "$ORIGEN/tar/$(basename "$rel")" "$DEST/$rel"
            for firma in "$ORIGEN/tar/$(basename "$rel")".asc "$ORIGEN/tar/$(basename "$rel")".sig; do
                [ -f "$firma" ] && cp "$firma" "$DEST/$(dirname "$rel")/"
            done
            ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pieza" "$(vf_lock_campo "$pieza" ref)" "$tipo" \
        "$(vf_lock_campo "$pieza" origen)" "$id" "$rel" "$(vf_sha256 "$DEST/$rel")" "$(vf_lock_campo "$pieza" rol)" \
        "$(vf_lock_campo "$pieza" sistemas)" "$(spdx_de "$pieza")" >> "$DEST/MANIFIESTO.tsv"
    vf_log "archivado $rel"
done
vf_log "fuentes listas en $DEST ($(($(wc -l < "$DEST/MANIFIESTO.tsv") - 1)) piezas)"
