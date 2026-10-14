#!/usr/bin/env bash
# tools/scancode.sh - deteccion de licencias con ScanCode sobre el fuente de cada pieza enlazada,
# contra una base REVISADA (notices/scancode-base.json). Un hallazgo nuevo para la release
# (FFMPEG-PROPIO.md, 2.5.5): una licencia que aparece en el fuente y que nadie ha revisado.
#
#   tools/scancode.sh <dir fuentes> <dir salida> [--estricto]
#
# Deja <dir salida>/scancode-<pieza>.json (resultado completo) y scancode-resumen.json:
# { pieza: [expresiones SPDX detectadas, ordenadas] }. Con la base en estado PENDIENTE (primera vez),
# el resumen es la propuesta de base: se revisa y se copia a notices/scancode-base.json. Con
# --estricto (release) falla si la base esta PENDIENTE o si hay expresiones que la base no tiene.
. "$(dirname "$0")/lib.sh"

FUENTES="$(cd "${1:?dir fuentes}" && pwd)"; SALIDA="${2:?dir salida}"; ESTRICTO="${3:-}"
mkdir -p "$SALIDA"; SALIDA="$(cd "$SALIDA" && pwd)"
VERSION_SC="$(vf_lock_campo scancode ref)"

if ! command -v scancode >/dev/null || ! scancode --version | grep -q "$VERSION_SC"; then
    python3 -m venv "$SALIDA/.venv"
    "$SALIDA/.venv/bin/pip" install --quiet "scancode-toolkit==$VERSION_SC"
    export PATH="$SALIDA/.venv/bin:$PATH"
fi
scancode --version

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for pieza in $(vf_lock_piezas "" fuente); do
    mkdir -p "$TMP/$pieza"
    vf_extraer "$FUENTES" "$pieza" "$TMP/$pieza"
    scancode --license --processes 4 --quiet --timeout 300 --json "$SALIDA/scancode-$pieza.json" "$TMP/$pieza"
    rm -rf "${TMP:?}/$pieza"
done

node - "$SALIDA" "$VF_RAIZ/notices/scancode-base.json" "$ESTRICTO" <<'EOF'
const fs = require('fs'), path = require('path');
const [dir, baseF, estricto] = process.argv.slice(2);
const resumen = {};
for (const f of fs.readdirSync(dir).filter(x => /^scancode-.+\.json$/.test(x) && x !== 'scancode-resumen.json')) {
  const pieza = f.slice('scancode-'.length, -'.json'.length);
  const j = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
  const s = new Set();
  for (const file of j.files || []) if (file.detected_license_expression_spdx) s.add(file.detected_license_expression_spdx);
  resumen[pieza] = [...s].sort();
}
fs.writeFileSync(path.join(dir, 'scancode-resumen.json'), JSON.stringify(resumen, null, 1) + '\n');
const base = JSON.parse(fs.readFileSync(baseF, 'utf8'));
if (base._estado === 'PENDIENTE') {
  console.log('scancode: la base esta PENDIENTE; scancode-resumen.json es la propuesta (revisarla y copiarla a notices/scancode-base.json)');
  process.exit(estricto === '--estricto' ? 1 : 0);
}
const nuevos = [];
for (const [p, exprs] of Object.entries(resumen)) for (const e of exprs) if (!(base[p] || []).includes(e)) nuevos.push(`${p}: ${e}`);
for (const n of nuevos) console.log('HALLAZGO NUEVO ' + n);
console.log(`scancode: ${Object.keys(resumen).length} piezas, ${nuevos.length} hallazgo(s) nuevo(s)`);
process.exit(nuevos.length && estricto === '--estricto' ? 1 : 0);
EOF
