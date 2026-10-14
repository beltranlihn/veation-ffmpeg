#!/usr/bin/env bash
# tools/lock.sh - consulta y comprobacion de versions.lock (FFMPEG-PROPIO.md, 2.3).
#
#   lock.sh get <pieza> <campo>              campo: sistemas tipo origen ref | rol commit sha256 digest gpg firma ...
#   lock.sh piezas [sistema] [roles] [tipo]  lista de piezas filtrada (roles separados por comas)
#   lock.sh archivo <pieza>                  ruta del archivo de la pieza dentro de fuentes/ y del paquete
#   lock.sh pendientes                       filas con algun valor PENDIENTE
#   lock.sh comprobar [--formato]            falla si:
#       - una fila esta mal formada (columnas, sistemas, tipo, rol, formato de commit/sha256/digest);
#       - una pieza no tiene su identidad fijada (PENDIENTE), salvo opcional:si; con --formato se
#         admite PENDIENTE (lo usa la comprobacion de cada push mientras el lock no esta congelado);
#       - xz esta en 5.6.0 o 5.6.1;
#       - una pieza fuente/toolchain no esta en la lista de piezas.conf (o al reves);
#       - un script de win/scripts.d no tiene fila en el lock (o su SCRIPT_COMMIT no es el del lock:
#         eso lo mide tools/aplicar-lock.sh --comprobar, que se llama desde aqui).

. "$(dirname "$0")/lib.sh"

comprobar() {
    local formato=0
    [ "${1:-}" = "--formato" ] && formato=1
    local fallos
    fallos="$(awk -v formato="$formato" '
        function mal(msg) { print "  " $1 ": " msg; n++ }
        function hex(v, len) { return length(v) == len && v ~ /^[0-9a-f]+$/ }
        /^[[:space:]]*(#|$)/ { next }
        {
            if (NF < 5) { mal("faltan columnas (pieza sistemas tipo origen ref)"); next }
            if (vista[$1]++) mal("pieza repetida")
            if ($2 !~ /^(win|mac|win,mac|ninguno)$/) mal("sistemas invalido: " $2)
            if ($3 !~ /^(git|tarball|oci|herramienta|referencia)$/) mal("tipo invalido: " $3)
            rol = ""; commit = ""; sha = ""; dig = ""; opcional = 0; gpg = ""; firma = ""
            for (i = 6; i <= NF; i++) {
                k = index($i, ":"); if (k == 0) { mal("columna sin clave:valor: " $i); continue }
                c = substr($i, 1, k - 1); v = substr($i, k + 1)
                if (c == "rol") rol = v
                else if (c == "commit") commit = v
                else if (c == "sha256") sha = v
                else if (c == "digest") dig = v
                else if (c == "opcional") opcional = (v == "si")
                else if (c == "gpg") gpg = v
                else if (c == "firma") firma = v
            }
            if (rol !~ /^(fuente|toolchain|herramienta|prueba|receta|referencia|instalador)$/) mal("rol invalido o ausente: " rol)
            pend = 0
            if ($3 == "git") {
                if (commit == "PENDIENTE") pend = 1
                else if (!hex(commit, 40)) mal("commit tiene que ser de 40 hex: " commit)
            }
            if ($3 == "tarball" || $3 == "herramienta") {
                if (sha == "PENDIENTE") pend = 1
                else if (!hex(sha, 64)) mal("sha256 tiene que ser de 64 hex: " sha)
                if ($4 == "PENDIENTE") pend = 1
            }
            if ($3 == "tarball" && commit != "" && commit != "PENDIENTE" && !hex(commit, 40)) mal("commit tiene que ser de 40 hex: " commit)
            if ($3 == "oci") {
                if (dig == "PENDIENTE") pend = 1
                else if (dig !~ /^sha256:[0-9a-f]+$/ || length(dig) != 71) mal("digest tiene que ser sha256:<64 hex>: " dig)
            }
            if ((gpg != "") != (firma != "")) mal("gpg: y firma: van juntas")
            if (gpg != "" && !(length(gpg) == 40 && gpg ~ /^[0-9A-F]+$/)) mal("huella gpg de 40 hex en mayusculas: " gpg)
            if (pend && !opcional && !formato) mal("identidad PENDIENTE (congelar con el workflow «congelar» o tools/congelar.sh)")
            if ($1 == "xz" && ($5 ~ /^v?5\.6\.[01]$/ || $4 ~ /5\.6\.[01]/)) mal("xz 5.6.0 y 5.6.1 estan prohibidas (puerta trasera CVE-2024-3094)")
        }
        END { exit 0 }' "$VF_LOCK")"
    local total=0
    if [ -n "$fallos" ]; then
        printf 'versions.lock:\n%s\n' "$fallos" >&2
        total=$(printf '%s\n' "$fallos" | wc -l | tr -d ' ')
    fi

    # piezas.conf <-> lock (lo mismo que mide piezas.sh comprobar, aqui solo la lista).
    local conf lock
    conf="$(vf_piezas_seccion piezas | awk '{ print $1, $2 }' | sort)"
    lock="$(awk '!/^[[:space:]]*(#|$)/ { for (i = 6; i <= NF; i++) if ($i == "rol:fuente" || $i == "rol:toolchain") print $1, $2 }' "$VF_LOCK" | sort)"
    if [ "$conf" != "$lock" ]; then
        vf_log "la lista de piezas.conf y las filas fuente/toolchain del lock no coinciden"
        diff <(printf '%s\n' "$conf") <(printf '%s\n' "$lock") >&2 || true
        total=$((total + 1))
    fi

    # scripts de win/ sin fila (y SCRIPT_COMMIT al dia, si el lock ya esta congelado)
    if [ "$formato" -eq 1 ]; then
        "$VF_RAIZ/tools/aplicar-lock.sh" --comprobar --formato || total=$((total + 1))
    else
        "$VF_RAIZ/tools/aplicar-lock.sh" --comprobar || total=$((total + 1))
    fi

    [ "$total" -eq 0 ] || vf_die "versions.lock: $total problema(s)"
    if [ "$formato" -eq 1 ]; then
        vf_log "versions.lock: formato correcto ($(pendientes | wc -l | tr -d ' ') fila(s) con PENDIENTE)"
    else
        vf_log "versions.lock: correcto y congelado"
    fi
}

pendientes() {
    awk '!/^[[:space:]]*(#|$)/ { for (i = 4; i <= NF; i++) if ($i == "PENDIENTE" || $i ~ /:PENDIENTE$/) { print $1; break } }' "$VF_LOCK"
}

orden="${1:-}"; shift || true
case "$orden" in
    get)        vf_lock_campo "${1:?pieza}" "${2:?campo}" ;;
    piezas)     vf_lock_piezas "${1:-}" "${2:-}" "${3:-}" ;;
    archivo)    vf_archivo_fuente "${1:?pieza}" ;;
    pendientes) pendientes ;;
    comprobar)  comprobar "${1:-}" ;;
    *) sed -n '2,16p' "$0" >&2; exit 2 ;;
esac
