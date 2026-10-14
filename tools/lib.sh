# tools/lib.sh - funciones comunes de los scripts de veation-ffmpeg.
#
# Se carga con «. tools/lib.sh» desde bash. Tiene que funcionar con el bash 3.2 de macOS y con el
# awk de BSD: nada de mapfile, arrays asociativos, ${var,,} ni extensiones de gawk.

set -euo pipefail

VF_RAIZ="${VF_RAIZ:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VF_LOCK="${VF_LOCK:-$VF_RAIZ/versions.lock}"
VF_PIEZAS="${VF_PIEZAS:-$VF_RAIZ/piezas.conf}"

vf_log() { printf '[%s] %s\n' "$(basename "$0")" "$*" >&2; }
vf_die() { printf '[%s] ERROR: %s\n' "$(basename "$0")" "$*" >&2; exit 1; }

# Descarga con reintentos de verdad. «--retry» solo no reintenta un corte a mitad de transferencia
# (curl 56, «Recv failure»): asi se cayo «congelar» con ftp.gnu.org, tras 10 minutos con la conexion
# colgada. --retry-all-errors reintenta cualquier fallo y --speed-limit/--speed-time cortan una
# transferencia parada (menos de 1 KB/s durante 60 s) para reintentarla en vez de esperar al TCP.
# La identidad no depende de esto: quien llama comprueba el sha256 o la firma de lo que baja.
vf_curl() {
    curl -fsSL --connect-timeout 30 --speed-limit 1024 --speed-time 60 \
        --retry 5 --retry-delay 10 --retry-all-errors "$@"
}

# vf_espejos <url>: la URL del lock y, si es de ftp.gnu.org, la misma ruta en espejos de GNU.
# ftp.gnu.org limita a los runners de GitHub: en «congelar» dejo de responder tras unas cuantas
# descargas seguidas (curl 28, sin conexion durante minutos). El lock sigue diciendo el origen
# canonico; el espejo es solo transporte y lo que baja se juzga igual, por sha256 o firma.
vf_espejos() {
    printf '%s\n' "$1"
    case "$1" in
        https://ftp.gnu.org/gnu/*)
            printf '%s\n' "https://mirrors.kernel.org/gnu/${1#https://ftp.gnu.org/gnu/}" \
                "https://ftpmirror.gnu.org/${1#https://ftp.gnu.org/gnu/}" ;;
    esac
}

# vf_descargar <url> <destino>: baja la URL (o, si falla, su espejo) a <destino>. Con espejos, cada
# intento lleva menos reintentos para no pasar minutos en un origen que no contesta.
vf_descargar() {
    local url="$1" destino="$2" u n reintentos
    n="$(vf_espejos "$url" | wc -l | tr -d ' ')"
    reintentos=5; [ "$n" -gt 1 ] && reintentos=2
    for u in $(vf_espejos "$url"); do
        [ "$u" = "$url" ] || vf_log "AVISO: $url no responde; se prueba el espejo $u"
        if vf_curl --retry "$reintentos" -o "$destino" "$u"; then return 0; fi
    done
    rm -f "$destino"
    vf_die "no se pudo bajar $url$([ "$n" -gt 1 ] && printf ' ni sus espejos')"
}

# SHA-256 de un archivo, igual en Linux, macOS y Git Bash.
vf_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Filas del lock sin comentarios ni lineas vacias.
vf_lock_filas() {
    awk '!/^[[:space:]]*(#|$)/' "$VF_LOCK"
}

# vf_lock_campo <pieza> <campo>
#   campo = sistemas | tipo | origen | ref | <clave> (rol, commit, sha256, digest, gpg, firma, ...)
#   Imprime el valor (vacio si la clave no existe). Falla si la pieza no existe.
vf_lock_campo() {
    local pieza="$1" campo="$2" salida
    salida="$(awk -v p="$pieza" -v c="$campo" '
        !/^[[:space:]]*(#|$)/ && $1 == p {
            encontrada = 1
            if (c == "sistemas") { print $2; exit }
            if (c == "tipo")     { print $3; exit }
            if (c == "origen")   { print $4; exit }
            if (c == "ref")      { print $5; exit }
            for (i = 6; i <= NF; i++) {
                n = index($i, ":")
                if (n > 0 && substr($i, 1, n - 1) == c) { print substr($i, n + 1); exit }
            }
            exit
        }
        END { if (!encontrada) exit 3 }' "$VF_LOCK")" || {
        [ $? -eq 3 ] && vf_die "la pieza «$pieza» no esta en versions.lock"
        return 1
    }
    printf '%s\n' "$salida"
}

# vf_lock_piezas [sistema] [roles separados por comas] [tipo]
#   Lista las piezas que cumplen los filtros (vacio = sin filtro).
vf_lock_piezas() {
    local sistema="${1:-}" roles="${2:-}" tipo="${3:-}"
    awk -v s="$sistema" -v r=",$roles," -v t="$tipo" '
        !/^[[:space:]]*(#|$)/ {
            if (s != "" && index("," $2 ",", "," s ",") == 0) next
            if (t != "" && $3 != t) next
            rol = ""
            for (i = 6; i <= NF; i++) if (substr($i, 1, 4) == "rol:") rol = substr($i, 5)
            if (r != ",," && index(r, "," rol ",") == 0) next
            print $1
        }' "$VF_LOCK"
}

# Nombre del archivo que una pieza ocupa dentro de fuentes/ (y del paquete de fuente).
#   git      -> bibliotecas|toolchain-win/<pieza>-<ref>-<commit12>.tar.xz
#   tarball  -> bibliotecas|toolchain-win/<nombre del archivo en el origen>
vf_archivo_fuente() {
    local pieza="$1" tipo rol carpeta
    tipo="$(vf_lock_campo "$pieza" tipo)"
    rol="$(vf_lock_campo "$pieza" rol)"
    case "$rol" in
        toolchain) carpeta="toolchain-win" ;;
        fuente)    carpeta="bibliotecas" ;;
        *) vf_die "«$pieza» (rol $rol) no forma parte de las fuentes" ;;
    esac
    [ "$pieza" = ffmpeg ] && carpeta="ffmpeg"
    case "$tipo" in
        git)
            local commit ref
            commit="$(vf_lock_campo "$pieza" commit)"
            ref="$(vf_lock_campo "$pieza" ref)"
            # Una ref que ya es el commit no se repite en el nombre.
            case "$ref" in "$commit"|"${commit:0:7}"*) ref="git" ;; esac
            printf '%s/%s-%s-%s.tar.xz\n' "$carpeta" "$pieza" "$ref" "${commit:0:12}" ;;
        tarball)
            printf '%s/%s\n' "$carpeta" "$(basename "$(vf_lock_campo "$pieza" origen)")" ;;
        *) vf_die "«$pieza» es de tipo $tipo: no tiene archivo de fuente" ;;
    esac
}

# vf_extraer <fuentes> <pieza> <destino>
# Extrae el arbol de una pieza desde las fuentes verificadas (salida de tools/archivar.sh o carpeta
# del paquete de fuente): busca la fila en MANIFIESTO.tsv, exige que la identidad sea la del lock,
# comprueba el sha256 del archivo y lo extrae quitando la carpeta de primer nivel. Si falta algo,
# FALLA: nunca va a buscarlo a la red (control negativo de verificar-fuente.yml).
vf_extraer() {
    local fuentes="$1" pieza="$2" destino="$3" fila id archivo sha esperado
    [ -f "$fuentes/MANIFIESTO.tsv" ] || vf_die "falta $fuentes/MANIFIESTO.tsv"
    fila="$(awk -F'\t' -v p="$pieza" '$1 == p' "$fuentes/MANIFIESTO.tsv")"
    [ -n "$fila" ] || vf_die "«$pieza» no esta en $fuentes/MANIFIESTO.tsv"
    id="$(printf '%s\n' "$fila" | cut -f5)"
    archivo="$fuentes/$(printf '%s\n' "$fila" | cut -f6)"
    sha="$(printf '%s\n' "$fila" | cut -f7)"
    case "$(vf_lock_campo "$pieza" tipo)" in
        git) esperado="$(vf_lock_campo "$pieza" commit)" ;;
        *)   esperado="$(vf_lock_campo "$pieza" sha256)" ;;
    esac
    [ "$id" = "$esperado" ] || vf_die "«$pieza»: las fuentes traen $id y el lock pide $esperado"
    [ -f "$archivo" ] || vf_die "«$pieza»: falta el archivo $archivo"
    [ "$(vf_sha256 "$archivo")" = "$sha" ] || vf_die "«$pieza»: el sha256 de $archivo no es el del manifiesto"
    rm -rf "$destino"
    mkdir -p "$destino"
    tar -xf "$archivo" -C "$destino" --strip-components=1
}

# verificar_firma <archivo> <url firma> <huella> [url de la clave publica]
# La clave se busca en los servidores de claves y, si no esta, en la URL del proyecto (clave: del lock).
# Venga de donde venga, solo vale si su huella es EXACTAMENTE la del lock.
verificar_firma() {
    local archivo="$1" url="$2" huella="$3" clave="${4:-}" firma gnupg estado
    case "$url" in *.sig) firma="$archivo.sig" ;; *) firma="$archivo.asc" ;; esac
    vf_descargar "$url" "$firma"
    gnupg="$(mktemp -d)"; chmod 700 "$gnupg"
    gpg --homedir "$gnupg" --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$huella" >/dev/null 2>&1 \
        || gpg --homedir "$gnupg" --batch --keyserver hkps://keys.openpgp.org --recv-keys "$huella" >/dev/null 2>&1 \
        || { [ -n "$clave" ] && vf_curl -o "$gnupg/clave.asc" "$clave" && gpg --homedir "$gnupg" --batch --import "$gnupg/clave.asc" >/dev/null 2>&1; } \
        || true
    if ! gpg --homedir "$gnupg" --batch --with-colons --fingerprint "$huella" 2>/dev/null | grep -q "^fpr:::::::::$huella:"; then
        rm -rf "$gnupg"
        vf_die "no se pudo obtener la clave $huella"
    fi
    estado="$(gpg --homedir "$gnupg" --batch --status-fd 1 --verify "$firma" "$archivo" 2>/dev/null || true)"
    rm -rf "$gnupg"
    printf '%s\n' "$estado" | grep -q "^\[GNUPG:\] VALIDSIG .* $huella\$" \
        || vf_die "firma de $(basename "$archivo") NO valida para la clave $huella"
    vf_log "firma valida: $(basename "$archivo") (clave $huella)"
}

# Valor de una opcion de piezas.conf de tipo clave=valor en una seccion ([global] por defecto).
vf_piezas_valor() {
    local clave="$1" seccion="${2:-global}"
    awk -v c="$clave" -v s="[$seccion]" '
        /^[[:space:]]*(#|$)/ { next }
        /^\[/ { dentro = ($0 == s); next }
        dentro { n = index($0, "="); if (n > 0 && substr($0, 1, n - 1) == c) { print substr($0, n + 1); exit } }
    ' "$VF_PIEZAS"
}

# Lineas de una seccion de piezas.conf (sin comentarios ni vacias), tal cual.
vf_piezas_seccion() {
    awk -v s="[$1]" '
        /^\[/ { dentro = ($0 == s); next }
        dentro && !/^[[:space:]]*(#|$)/ { print }
    ' "$VF_PIEZAS"
}

# Sufijo de version (--extra-version de configure-comun), p. ej. veation.1
vf_extra_version() {
    vf_piezas_seccion configure-comun | awk -F= '$1 == "--extra-version" { print $2; exit }'
}

# Version visible del binario: <ffmpeg>-<extra>, p. ej. 8.1.3-veation.1
vf_version() {
    printf '%s-%s\n' "$(vf_lock_campo ffmpeg ref)" "$(vf_extra_version)"
}
