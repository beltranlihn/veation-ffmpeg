#!/usr/bin/env bash
# tools/aplicar-lock.sh - escribe en cada script de win/scripts.d la identidad de su pieza segun
# versions.lock (FFMPEG-PROPIO.md, 2.4.2).
#
#   aplicar-lock.sh                         reescribe el bloque «>>> veation ... <<< veation» de cada script
#   aplicar-lock.sh --comprobar [--formato] no escribe nada; falla si:
#       - un script no tiene bloque o su SCRIPT_PIEZA no es una pieza de Windows del lock;
#       - el bloque no es el que se generaria hoy desde el lock (deriva);
#       - una pieza fuente de Windows (salvo ffmpeg, que compila build.sh) no tiene script, o tiene dos.
#     Con --formato se admite que el lock tenga PENDIENTE (comprobacion de cada push antes de congelar).
#
# El bloque lleva SCRIPT_PIEZA, SCRIPT_REPO (origen) y SCRIPT_COMMIT (git) o SCRIPT_SHA256 (tarball).
# SCRIPT_COMMIT/SCRIPT_SHA256 entran en la cadena de descarga de la etapa (util/dl_functions.sh), asi
# que un cambio del lock invalida la cache de esa etapa y solo de esa.

. "$(dirname "$0")/lib.sh"

SCRIPTS_DIR="$VF_RAIZ/win/scripts.d"
comprobar=0; formato=0
for a in "$@"; do
    case "$a" in
        --comprobar) comprobar=1 ;;
        --formato)   formato=1 ;;
        *) vf_die "opcion desconocida: $a" ;;
    esac
done

bloque() {
    local pieza="$1" tipo
    echo '# >>> veation: bloque que escribe tools/aplicar-lock.sh desde versions.lock (no editar a mano)'
    echo "SCRIPT_PIEZA=\"$pieza\""
    if [ "$pieza" != "-" ]; then
        tipo="$(vf_lock_campo "$pieza" tipo)"
        echo "SCRIPT_REPO=\"$(vf_lock_campo "$pieza" origen)\""
        case "$tipo" in
            git)     echo "SCRIPT_COMMIT=\"$(vf_lock_campo "$pieza" commit)\"" ;;
            tarball) echo "SCRIPT_SHA256=\"$(vf_lock_campo "$pieza" sha256)\"" ;;
            *) vf_die "$pieza es de tipo $tipo: un script de scripts.d solo puede ser de una pieza git o tarball" ;;
        esac
    fi
    echo '# <<< veation'
}

fallos=0
usadas=""
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for script in "$SCRIPTS_DIR"/*.sh "$SCRIPTS_DIR"/*/*.sh; do
    [ -f "$script" ] || continue
    rel="${script#$VF_RAIZ/}"
    pieza="$(awk -F'"' '/^SCRIPT_PIEZA=/ { print $2; exit }' "$script")"
    if ! grep -q '^# >>> veation' "$script" || [ -z "$pieza" ]; then
        vf_log "$rel: no tiene el bloque veation con SCRIPT_PIEZA"
        fallos=$((fallos + 1)); continue
    fi
    if [ "$pieza" != "-" ]; then
        sistemas="$(vf_lock_campo "$pieza" sistemas 2>/dev/null)" || { vf_log "$rel: la pieza «${pieza}» no esta en versions.lock"; fallos=$((fallos + 1)); continue; }
        case ",$sistemas," in *,win,*) ;; *) vf_log "$rel: «${pieza}» no es una pieza de Windows en el lock ($sistemas)"; fallos=$((fallos + 1)); continue ;; esac
        id="$(vf_lock_campo "$pieza" commit)$(vf_lock_campo "$pieza" sha256)"
        case "$id" in
            *PENDIENTE*)
                if [ "$comprobar" -eq 1 ] && [ "$formato" -eq 0 ]; then
                    vf_log "$rel: «${pieza}» sigue PENDIENTE en el lock"
                    fallos=$((fallos + 1))
                fi ;;
        esac
        usadas="$usadas $pieza"
    fi
    # Archivo con el bloque regenerado
    bloque "$pieza" > "$tmp.bloque"
    awk -v archivo="$tmp.bloque" '
        /^# >>> veation/ { while ((getline l < archivo) > 0) print l; salto = 1; next }
        salto && /^# <<< veation/ { salto = 0; next }
        !salto { print }
    ' "$script" > "$tmp"
    if [ "$comprobar" -eq 1 ]; then
        if ! cmp -s "$tmp" "$script"; then
            vf_log "$rel: el bloque no corresponde a versions.lock (ejecutar tools/aplicar-lock.sh):"
            diff "$script" "$tmp" >&2 || true
            fallos=$((fallos + 1))
        fi
    else
        if ! cmp -s "$tmp" "$script"; then
            cat "$tmp" > "$script"
            vf_log "actualizado $rel"
        fi
    fi
done
rm -f "$tmp.bloque"

# Cada pieza fuente o toolchain de Windows compilada por una etapa tiene exactamente un script.
# ffmpeg lo compila build.sh; el resto de la toolchain (gcc, binutils...) lo compila crosstool-ng.
for p in $(vf_lock_piezas win fuente) mingw-w64; do
    [ "$p" = ffmpeg ] && continue
    n=0
    for u in $usadas; do [ "$u" = "$p" ] && n=$((n + 1)); done
    if [ "$n" -ne 1 ]; then
        vf_log "la pieza «${p}» tiene $n script(s) en win/scripts.d (tiene que tener 1)"
        fallos=$((fallos + 1))
    fi
done

[ "$fallos" -eq 0 ] || vf_die "aplicar-lock: $fallos problema(s)"
[ "$comprobar" -eq 1 ] && vf_log "win/scripts.d: al dia con versions.lock"
exit 0
