#!/usr/bin/env bash
# tools/piezas.sh - lee piezas.conf (la unica lista de piezas y de opciones de configure).
#
#   piezas.sh args <sistema>           argumentos de configure, uno por linea (sistema: win, mac-arm64, mac-x86_64)
#   piezas.sh buildconf <sistema>      lo que tiene que imprimir «ffmpeg -buildconf», normalizado
#   piezas.sh codificadores <sistema>  la lista blanca de codificadores (nombres de configure, admite *)
#   piezas.sh seccion <nombre>         lineas de una seccion
#   piezas.sh valor <clave>            valor de [global]
#   piezas.sh comprobar                expected/ al dia, orden de opciones, coherencia con el lock
#
# «buildconf» reproduce exactamente lo que hace FFmpeg 8.1.3: configure guarda los argumentos con
# sh_quote() (configure, linea 616) y fftools/opt_common.c los parte por « --», salvo que el trozo
# anterior acabe en «pkg-config» (por eso --pkg-config=pkg-config sale pegado a la opcion siguiente).

. "$(dirname "$0")/lib.sh"

SISTEMAS="win mac-arm64 mac-x86_64"

secciones_de() {
    case "$1" in
        win)        echo "configure-entorno-win configure-comun configure-win" ;;
        mac-arm64)  echo "configure-entorno-mac-arm64 configure-comun configure-mac configure-mac-arm64" ;;
        mac-x86_64) echo "configure-entorno-mac-x86_64 configure-comun configure-mac configure-mac-x86_64" ;;
        *) vf_die "sistema desconocido: «$1» (win, mac-arm64, mac-x86_64)" ;;
    esac
}

args() {
    local s
    for s in $(secciones_de "$1"); do vf_piezas_seccion "$s"; done
}

# FFMPEG_CONFIGURATION tal como lo deja configure, y despues el corte de print_buildconf().
buildconf() {
    args "$1" | awk -v q="'" '
        function sh_quote(v,   w) {
            w = v
            gsub(q, q "\\\\" q q, w)
            if (w ~ /[^A-Za-z0-9_\/.+-]/) w = q w q
            return w
        }
        {
            v = $0
            n = index(v, "=")
            if (n > 0) { l = substr(v, 1, n); r = substr(v, n + 1) } else { l = ""; r = v }
            conf = conf (NR == 1 ? "" : " ") l sh_quote(r)
        }
        END {
            s = conf
            # « --» -> «~--»
            out = ""
            while ((i = index(s, " --")) > 0) { out = out substr(s, 1, i - 1) "~--"; s = substr(s, i + 3) }
            s = out s
            # «pkg-config~» -> «pkg-config »
            out = ""
            while ((i = index(s, "pkg-config~")) > 0) { out = out substr(s, 1, i - 1) "pkg-config "; s = substr(s, i + 11) }
            s = out s
            m = split(s, partes, "~")
            for (k = 1; k <= m; k++) if (partes[k] != "") print partes[k]
        }'
}

codificadores() {
    args "$1" | awk -F= '$1 == "--enable-encoder" { n = split($2, a, ","); for (i = 1; i <= n; i++) print a[i] }'
}

comprobar() {
    local fallos=0 s esperado tmp minimo
    tmp="$(mktemp)"
    for s in $SISTEMAS; do
        esperado="$VF_RAIZ/expected/buildconf-$s.txt"
        buildconf "$s" > "$tmp"
        if [ ! -f "$esperado" ]; then
            vf_log "FALTA expected/buildconf-$s.txt (generarlo con: tools/piezas.sh buildconf $s > expected/buildconf-$s.txt)"
            fallos=$((fallos + 1))
        elif ! diff -u "$esperado" "$tmp" >&2; then
            vf_log "expected/buildconf-$s.txt no coincide con piezas.conf (diferencia arriba)"
            fallos=$((fallos + 1))
        fi
        # --disable-encoders antes de cualquier --enable-encoder
        if ! args "$s" | awk '/^--disable-encoders$/ { d = 1 } /^--enable-encoder=/ && !d { exit 1 }'; then
            vf_log "$s: hay un --enable-encoder antes de --disable-encoders"
            fallos=$((fallos + 1))
        fi
        # ninguna opcion con comillas de shell: cada linea es un argumento literal
        if args "$s" | grep -q "['\"]"; then
            vf_log "$s: piezas.conf no admite comillas de shell en las opciones"
            fallos=$((fallos + 1))
        fi
    done
    # El minimo de macOS de [global] es el de las opciones del Mac.
    minimo="$(vf_piezas_valor macos-min)"
    if vf_piezas_seccion configure-mac | grep -o 'mmacosx-version-min=[0-9.]*' | grep -v -x "mmacosx-version-min=$minimo" >/dev/null; then
        vf_log "configure-mac usa un -mmacosx-version-min distinto de macos-min=$minimo"
        fallos=$((fallos + 1))
    fi
    # [piezas] == filas rol:fuente + rol:toolchain del lock, con los mismos sistemas.
    local lista_conf lista_lock
    lista_conf="$(vf_piezas_seccion piezas | awk '{ print $1, $2 }' | sort)"
    lista_lock="$(awk '!/^[[:space:]]*(#|$)/ { for (i = 6; i <= NF; i++) if ($i == "rol:fuente" || $i == "rol:toolchain") print $1, $2 }' "$VF_LOCK" | sort)"
    if [ "$lista_conf" != "$lista_lock" ]; then
        vf_log "las piezas de piezas.conf y las filas fuente/toolchain de versions.lock no coinciden:"
        diff <(printf '%s\n' "$lista_conf") <(printf '%s\n' "$lista_lock") >&2 || true
        fallos=$((fallos + 1))
    fi
    rm -f "$tmp"
    [ "$fallos" -eq 0 ] || vf_die "piezas.conf: $fallos comprobacion(es) en rojo"
    vf_log "piezas.conf: correcto"
}

orden="${1:-}"; shift || true
case "$orden" in
    args)          args "${1:?falta el sistema}" ;;
    buildconf)     buildconf "${1:?falta el sistema}" ;;
    codificadores) codificadores "${1:?falta el sistema}" ;;
    seccion)       vf_piezas_seccion "${1:?falta la seccion}" ;;
    valor)         vf_piezas_valor "${1:?falta la clave}" ;;
    comprobar)     comprobar ;;
    *) sed -n '2,12p' "$0" >&2; exit 2 ;;
esac
