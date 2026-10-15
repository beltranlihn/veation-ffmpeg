#!/usr/bin/env bash
# tools/fetch.sh - descarga todo lo que va al paquete de fuente (rol fuente y toolchain del lock) y lo
# VERIFICA contra versions.lock (FFMPEG-PROPIO.md, 2.5.1). No archiva: eso es tools/archivar.sh.
#
#   tools/fetch.sh <dir>
#
# Deja en <dir>:
#   arbol/<pieza>/          arbol exacto de cada pieza git, sin .git (y solo las rutas de solo:, si las hay)
#   arbol/<pieza>.epoch     fecha del commit (segundos), para que el tar sea determinista
#   tar/<archivo>           cada tarball tal como lo publica el proyecto (y su firma, si el lock la pide)
#
# Comprobaciones (cualquier fallo para la descarga entera):
#   git      el commit descargado es el del lock (rev-parse) y, si ref es una etiqueta, la etiqueta
#            remota sigue apuntando a ese commit (una etiqueta movida es una alarma, no un detalle);
#   tarball  sha256 == lock; con gpg:/firma:, la firma es VALIDA y de esa huella exacta (FFmpeg).
. "$(dirname "$0")/lib.sh"

DIR="${1:?uso: tools/fetch.sh <dir>}"
mkdir -p "$DIR/arbol" "$DIR/tar"
DIR="$(cd "$DIR" && pwd)"
export GIT_TERMINAL_PROMPT=0

bajar_tarball() {
    local pieza="$1" url sha destino gpg firma
    url="$(vf_lock_campo "$pieza" origen)"
    sha="$(vf_lock_campo "$pieza" sha256)"
    destino="$DIR/tar/$(basename "$url")"
    case "$sha" in PENDIENTE|"") vf_die "«${pieza}» sin sha256 en el lock (congelar primero)" ;; esac
    if [ ! -f "$destino" ] || [ "$(vf_sha256 "$destino")" != "$sha" ]; then
        vf_descargar "$url" "$destino.part"
        mv "$destino.part" "$destino"
    fi
    [ "$(vf_sha256 "$destino")" = "$sha" ] || vf_die "«${pieza}»: sha256 de $(basename "$url") distinto del lock"
    gpg="$(vf_lock_campo "$pieza" gpg)"; firma="$(vf_lock_campo "$pieza" firma)"
    [ -z "$gpg" ] || verificar_firma "$destino" "$firma" "$gpg" "$(vf_lock_campo "$pieza" clave)"
    vf_log "ok $pieza: $(basename "$url") sha256 $sha"
}

bajar_git() {
    local pieza="$1" url ref commit arbol remoto solo
    url="$(vf_lock_campo "$pieza" origen)"
    ref="$(vf_lock_campo "$pieza" ref)"
    commit="$(vf_lock_campo "$pieza" commit)"
    solo="$(vf_lock_campo "$pieza" solo)"
    case "$commit" in PENDIENTE|"") vf_die "«${pieza}» sin commit en el lock (congelar primero)" ;; esac
    arbol="$DIR/arbol/$pieza"
    rm -rf "$arbol" "$arbol.git"; mkdir -p "$arbol.git"
    git -C "$arbol.git" init -q
    git -C "$arbol.git" remote add origin "$url"
    # 1) por commit (GitHub, GitLab y googlesource lo admiten); 2) por etiqueta; 3) historia completa
    git -C "$arbol.git" fetch -q --depth=1 origin "$commit" 2>/dev/null \
        || git -C "$arbol.git" fetch -q --depth=1 origin "refs/tags/$ref:refs/tags/$ref" 2>/dev/null \
        || git -C "$arbol.git" fetch -q origin
    git -C "$arbol.git" -c advice.detachedHead=false checkout -q --detach "$commit"
    [ "$(git -C "$arbol.git" rev-parse HEAD)" = "$commit" ] || vf_die "«${pieza}»: el commit descargado no es el del lock"
    # Si ref es una etiqueta, que siga apuntando a ese commit
    remoto="$(git ls-remote "$url" "refs/tags/$ref^{}" "refs/tags/$ref" | awk 'NR == 1 || /\^\{\}$/ { c = $1 } END { print c }')"
    if [ -n "$remoto" ] && [ "$remoto" != "$commit" ]; then
        vf_die "«${pieza}»: la etiqueta $ref apunta ahora a $remoto y el lock dice $commit (¿etiqueta movida?)"
    fi
    git -C "$arbol.git" log -1 --format=%ct HEAD > "$arbol.epoch"
    if [ -n "$solo" ]; then
        mkdir -p "$arbol"
        local IFS=,
        for p in $solo; do
            [ -e "$arbol.git/$p" ] || vf_die "«${pieza}»: la ruta $p de solo: no existe en $ref"
            mkdir -p "$arbol/$(dirname "$p")"
            cp -R "$arbol.git/$p" "$arbol/$p"
        done
        unset IFS
        rm -rf "$arbol.git"
    else
        rm -rf "$arbol.git/.git"
        mv "$arbol.git" "$arbol"
    fi
    vf_log "ok $pieza: $ref = $commit${solo:+ (solo $solo)}"
}

for pieza in $(vf_lock_piezas "" fuente,toolchain); do
    case "$(vf_lock_campo "$pieza" tipo)" in
        git)     bajar_git "$pieza" ;;
        tarball) bajar_tarball "$pieza" ;;
        *) vf_die "«${pieza}»: tipo no descargable" ;;
    esac
done
vf_log "todo descargado y verificado en $DIR"
