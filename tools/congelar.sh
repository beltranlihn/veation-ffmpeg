#!/usr/bin/env bash
# tools/congelar.sh - calcula los valores PENDIENTE de versions.lock y los escribe (FFMPEG-PROPIO.md,
# 2.3 y 6, fase 1: «congelar los sha256 y los commits que hoy figuran como <...>»). No inventa nada:
# cada valor sale de una fuente que se puede repetir.
#
#   tools/congelar.sh [--solo <pieza>] [--comprobar-congelados]
#
#   git        ref = etiqueta  -> git ls-remote (commit al que apunta la etiqueta, desreferenciada)
#              ref = hash corto -> clon sin blobs + rev-parse (el commit completo; falla si es ambiguo)
#              resolver:rev-count, ref = r<N> -> el commit con N commits en su historia (x264 r3223),
#                                                comprobado con «git rev-list --count»
#   tarball / herramienta -> descarga, firma OpenPGP si el lock la pide (gpg:/firma:), sha256 del archivo;
#              con contenido:<ruta>=<sha256>, ademas comprueba ese archivo de dentro (juez de las pruebas)
#   oci        -> digest del indice (docker buildx imagetools inspect)
#   ffmpeg     -> ademas, la etiqueta n8.1.3 tiene que apuntar al commit:… del lock
#
# --comprobar-congelados vuelve a calcular TAMBIEN lo ya congelado y falla si algo cambio (una etiqueta
# movida, un tarball resubido). Lo usa el job «fuentes» de verificar-fuente.yml una vez al mes.
#
# Al terminar ejecuta tools/aplicar-lock.sh (los scripts de win/scripts.d llevan el commit/sha256) y
# tools/lock.sh comprobar. El resultado SE REVISA y se versiona a mano: el workflow «congelar» lo deja
# como artefacto (versions.lock + congelar.patch) y en el resumen del job.
. "$(dirname "$0")/lib.sh"

SOLO=""; RECOMPROBAR=0
while [ $# -gt 0 ]; do
    case "$1" in
        --solo) SOLO="$2"; shift 2 ;;
        --comprobar-congelados) RECOMPROBAR=1; shift ;;
        *) vf_die "opcion desconocida: $1" ;;
    esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_TERMINAL_PROMPT=0
cambios=0; discrepancias=0

# poner <pieza> <clave> <valor>: sustituye clave:VIEJO por clave:valor en la fila de la pieza
poner() {
    local pieza="$1" clave="$2" valor="$3"
    awk -v p="$pieza" -v c="$clave" -v v="$valor" '
        !/^[[:space:]]*(#|$)/ && $1 == p {
            n = split($0, partes, /[ ]+/); linea = $0
            for (i = 1; i <= n; i++) if (index(partes[i], c ":") == 1) { viejo = partes[i] }
            if (viejo != "") { k = index(linea, viejo); linea = substr(linea, 1, k - 1) c ":" v substr(linea, k + length(viejo)) }
            print linea; next
        }
        { print }' "$VF_LOCK" > "$TMP/lock" && cat "$TMP/lock" > "$VF_LOCK"
}

# anotar <pieza> <clave> <valor calculado>
anotar() {
    local pieza="$1" clave="$2" nuevo="$3" actual
    actual="$(vf_lock_campo "$pieza" "$clave")"
    if [ "$actual" = PENDIENTE ]; then
        poner "$pieza" "$clave" "$nuevo"
        cambios=$((cambios + 1))
        printf '| %s | %s | %s |\n' "$pieza" "$clave" "$nuevo" >> "$TMP/resumen"
        vf_log "congelado $pieza $clave:$nuevo"
    elif [ "$actual" != "$nuevo" ]; then
        discrepancias=$((discrepancias + 1))
        vf_log "DISCREPANCIA $pieza $clave: el lock dice $actual y hoy sale $nuevo"
        printf '| %s | %s | DISCREPANCIA: lock %s, hoy %s |\n' "$pieza" "$clave" "$actual" "$nuevo" >> "$TMP/resumen"
    fi
}

hace_falta() {   # hace_falta <pieza> <clave>: hay que calcularlo?
    [ "$RECOMPROBAR" -eq 1 ] || [ "$(vf_lock_campo "$1" "$2")" = PENDIENTE ]
}

commit_de_etiqueta() {   # commit_de_etiqueta <url> <etiqueta>
    git ls-remote "$1" "refs/tags/$2^{}" "refs/tags/$2" | awk 'NR == 1 || /\^\{\}$/ { c = $1 } END { print c }'
}

congelar_git() {
    local pieza="$1" url ref resolver commit clon n
    url="$(vf_lock_campo "$pieza" origen)"; ref="$(vf_lock_campo "$pieza" ref)"
    resolver="$(vf_lock_campo "$pieza" resolver)"
    hace_falta "$pieza" commit || return 0
    if [ "$resolver" = rev-count ]; then
        n="${ref#r}"
        clon="$TMP/clon-$pieza"
        git clone -q --filter=blob:none --no-checkout "$url" "$clon"
        commit="$(git -C "$clon" rev-list --reverse HEAD | sed -n "${n}p")"
        [ -n "$commit" ] || vf_die "$pieza: la rama principal no tiene $n commits"
        [ "$(git -C "$clon" rev-list --count "$commit")" = "$n" ] || vf_die "$pieza: $commit no tiene $n commits en su historia"
    elif printf '%s' "$ref" | grep -Eq '^[0-9a-f]{7,40}$'; then
        clon="$TMP/clon-$pieza"
        git clone -q --filter=blob:none --no-checkout "$url" "$clon"
        commit="$(git -C "$clon" rev-parse --verify --quiet "$ref^{commit}")" || vf_die "$pieza: $ref no existe o es ambiguo"
    else
        commit="$(commit_de_etiqueta "$url" "$ref")"
        [ -n "$commit" ] || vf_die "$pieza: la etiqueta $ref no existe en $url"
    fi
    printf '%s' "$commit" | grep -Eq '^[0-9a-f]{40}$' || vf_die "$pieza: commit invalido «$commit»"
    anotar "$pieza" commit "$commit"
}

congelar_archivo() {
    local pieza="$1" url archivo gpg firma clave contenido ruta esperado real
    url="$(vf_lock_campo "$pieza" origen)"
    [ "$url" = PENDIENTE ] && { vf_log "AVISO: «$pieza» sin URL (lo tiene que fijar una persona)"; return 0; }
    hace_falta "$pieza" sha256 || return 0
    archivo="$TMP/$(basename "$url")"
    curl -fsSL --retry 5 --retry-delay 5 -o "$archivo" "$url"
    gpg="$(vf_lock_campo "$pieza" gpg)"
    if [ -n "$gpg" ]; then
        firma="$(vf_lock_campo "$pieza" firma)"; clave="$(vf_lock_campo "$pieza" clave)"
        verificar_firma "$archivo" "$firma" "$gpg" "$clave"
    fi
    contenido="$(vf_lock_campo "$pieza" contenido)"
    if [ -n "$contenido" ]; then
        ruta="${contenido%%=*}"; esperado="${contenido#*=}"
        mkdir -p "$TMP/x-$pieza"
        (cd "$TMP/x-$pieza" && unzip -q "$archivo" "$ruta")
        real="$(vf_sha256 "$TMP/x-$pieza/$ruta")"
        [ "$real" = "$esperado" ] || vf_die "$pieza: $ruta tiene sha256 $real y se esperaba $esperado"
    fi
    anotar "$pieza" sha256 "$(vf_sha256 "$archivo")"
    rm -f "$archivo"
}

congelar_oci() {
    local pieza="$1" imagen digest
    hace_falta "$pieza" digest || return 0
    imagen="$(vf_lock_campo "$pieza" origen)"
    # A archivo y despues awk: con «| awk '... exit'» el awk cerraba la tuberia en la tercera linea,
    # buildx moria por SIGPIPE escribiendo el resto de los manifiestos y docker devolvia 255 sin
    # mensaje (pipefail + set -e: congelar paraba en seco tras la ultima pieza anterior).
    docker buildx imagetools inspect "$imagen" > "$TMP/oci-$pieza.txt"
    digest="$(awk '$1 == "Digest:" { print $2; exit }' "$TMP/oci-$pieza.txt")"
    printf '%s' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || vf_die "$pieza: digest invalido «$digest»"
    anotar "$pieza" digest "$digest"
}

: > "$TMP/resumen"
for pieza in $(awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$VF_LOCK"); do
    [ -n "$SOLO" ] && [ "$pieza" != "$SOLO" ] && continue
    case "$(vf_lock_campo "$pieza" tipo)" in
        git)                 congelar_git "$pieza" ;;
        tarball|herramienta) congelar_archivo "$pieza" ;;
        oci)                 congelar_oci "$pieza" ;;
        referencia)          ;;
    esac
done

# FFmpeg: el tarball corresponde a la etiqueta del lock
if [ -z "$SOLO" ] || [ "$SOLO" = ffmpeg ]; then
    et="$(vf_lock_campo ffmpeg etiqueta)"; c="$(vf_lock_campo ffmpeg commit)"
    real="$(commit_de_etiqueta https://github.com/FFmpeg/FFmpeg.git "$et")"
    [ "$real" = "$c" ] || vf_die "la etiqueta $et de FFmpeg apunta a $real y el lock dice $c"
fi

"$VF_RAIZ/tools/aplicar-lock.sh"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### congelar: $cambios valor(es) calculado(s), $discrepancias discrepancia(s)"
        echo
        echo '| pieza | clave | valor |'
        echo '|---|---|---|'
        cat "$TMP/resumen"
    } >> "$GITHUB_STEP_SUMMARY"
fi
vf_log "congelar: $cambios valor(es) nuevo(s), $discrepancias discrepancia(s)"
[ "$discrepancias" -eq 0 ] || vf_die "hay valores ya congelados que hoy salen distintos: revisar antes de nada"
vf_log "pendientes que quedan: $("$VF_RAIZ/tools/lock.sh" pendientes | tr '\n' ' ')"
