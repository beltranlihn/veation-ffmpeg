#!/usr/bin/env bash
# tools/comprobar-repo.sh - lo que se puede comprobar sin compilar nada (workflow «comprobar», en cada
# push y pull request; tambien sirve en local antes de un commit).
#
#   tools/comprobar-repo.sh [--congelado]
#
#   - sintaxis de todos los scripts (bash -n) y de todo el JavaScript (node --check);
#   - cada «uses:» de los workflows fijado por SHA completo (40 hex) y los YAML legibles;
#   - versions.lock bien formado (con --congelado, ademas sin PENDIENTE), piezas.conf y expected/ al
#     dia, win/scripts.d al dia con el lock, y toda modificacion de un fuente inventariada;
#   - los .ps1 en ASCII (PowerShell 5.1 los lee como ANSI) y ningun archivo con CRLF.
. "$(dirname "$0")/lib.sh"
cd "$VF_RAIZ"
fallos=0
rojo() { vf_log "ROJO: $*"; fallos=$((fallos + 1)); }

for f in $(git ls-files '*.sh'); do bash -n "$f" || rojo "sintaxis de $f"; done
for f in $(git ls-files '*.mjs' '*.js'); do node --check "$f" || rojo "sintaxis de $f"; done

for f in $(git ls-files '.github/workflows/*.yml'); do
    while IFS= read -r l; do
        printf '%s\n' "$l" | grep -Eq 'uses:[[:space:]]*[^@[:space:]]+@[0-9a-f]{40}([[:space:]]+#.*)?$' \
            || rojo "$f: «uses:» sin SHA completo: $(echo $l)"
    done < <(grep -E '^[[:space:]-]*uses:' "$f" | grep -v 'uses:[[:space:]]*\./')
    if command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
        python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$f" || rojo "$f no es YAML valido"
    fi
done

if [ "${1:-}" = "--congelado" ]; then tools/lock.sh comprobar || fallos=$((fallos + 1))
else tools/lock.sh comprobar --formato || fallos=$((fallos + 1)); fi
tools/piezas.sh comprobar || fallos=$((fallos + 1))
tools/modificaciones.sh || fallos=$((fallos + 1))

for f in $(git ls-files '*.ps1'); do iconv -f ASCII -t ASCII "$f" >/dev/null 2>&1 || rojo "$f no es ASCII"; done
for f in $(git ls-files); do [ -f "$f" ] && grep -Iq $'\r' "$f" && rojo "$f tiene CRLF"; done

[ "$fallos" -eq 0 ] || vf_die "$fallos comprobacion(es) en rojo"
vf_log "repositorio: todo en verde"
