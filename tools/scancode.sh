#!/usr/bin/env bash
# tools/scancode.sh - deteccion de licencias con ScanCode sobre el fuente de TODO lo que acaba dentro del
# binario, contra una base REVISADA (notices/scancode-base.json), y comprobacion de que cada licencia
# aceptada esta AVISADA (FFMPEG-PROPIO.md, 2.5.5).
#
#   tools/scancode.sh <dir fuentes> <dir salida> [--estricto]
#
# 1. Escanea el fuente de cada pieza rol:fuente del lock y, del runtime de Windows que va enlazado en
#    ffmpeg.exe, gcc (libgcc/ y libstdc++-v3/, sin testsuite/ ni doc/) y mingw-w64 (mingw-w64-crt/ y
#    mingw-w64-libraries/winpthreads/).
# 2. Escanea los textos que publica FFMPEG-NOTICES.txt (tools/avisos.mjs textos) para saber que licencias
#    quedan cubiertas en cada pieza.
# 3. Compara con la base:
#      { "_estado": ..., "piezas": { "<pieza>": { "<expresion SPDX>": "<como se cumple>" } } }
#    «como se cumple» es "textos" (todas las licencias de la expresion aparecen en los textos de esa
#    pieza) o una justificacion ESCRITA (p. ej. «solo en tests/, no se compila»). Aceptar una licencia en
#    la base no basta: si pide aviso, o esta en los textos o la base dice por que no hace falta.
#
# Deja <dir salida>/scancode-<pieza>.json (resultado completo), scancode-textos.json,
# scancode-resumen.json ({ pieza: [expresiones] }) y scancode-propuesta.json (la base propuesta: "textos"
# donde los textos ya cubren, PENDIENTE donde hace falta un texto nuevo o una justificacion).
# Con --estricto (release) falla si la base esta PENDIENTE, si hay una expresion que la base no tiene, si
# una entrada no tiene justificacion o si una entrada "textos" no esta cubierta por los textos.
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

# Que parte del arbol de cada pieza se escanea (lo que se compila dentro del binario).
subarboles() {
    case "$1" in
        gcc)       echo "libgcc libstdc++-v3" ;;
        mingw-w64) echo "mingw-w64-crt mingw-w64-libraries/winpthreads" ;;
        *)         echo "." ;;
    esac
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for pieza in $(vf_lock_piezas "" fuente) gcc mingw-w64; do
    vf_extraer "$FUENTES" "$pieza" "$TMP/arbol"
    rm -rf "$TMP/escanear"; mkdir -p "$TMP/escanear"
    for s in $(subarboles "$pieza"); do
        [ -e "$TMP/arbol/$s" ] || vf_die "«${pieza}»: no existe $s en su fuente"
        if [ "$s" = . ]; then rm -rf "$TMP/escanear"; mv "$TMP/arbol" "$TMP/escanear"; break; fi
        mkdir -p "$TMP/escanear/$(dirname "$s")"; mv "$TMP/arbol/$s" "$TMP/escanear/$s"
    done
    rm -rf "$TMP/escanear/libstdc++-v3/testsuite" "$TMP/escanear/libstdc++-v3/doc" "$TMP/arbol"
    scancode --license --processes 4 --quiet --timeout 300 --json "$SALIDA/scancode-$pieza.json" "$TMP/escanear"
    rm -rf "$TMP/escanear"
done

# Los textos que se publican, escaneados igual
node "$VF_RAIZ/tools/avisos.mjs" textos --fuentes "$FUENTES" --salida "$TMP/avisos"
scancode --license --processes 4 --quiet --timeout 300 --json "$SALIDA/scancode-textos.json" "$TMP/avisos/licencias"

node - "$SALIDA" "$VF_RAIZ/notices/scancode-base.json" "$ESTRICTO" <<'EOF'
const fs = require('fs'), path = require('path');
const [dir, baseF, estricto] = process.argv.slice(2);
const exprDe = (file) => file.detected_license_expression_spdx;
// Licencias de una expresion SPDX: «A AND (B OR C) WITH D» -> A B C D
const claves = (e) => e.replace(/[()]/g, ' ').split(/\s+(?:AND|OR|WITH)\s+|\s+/).map(s => s.trim()).filter(Boolean);

const resumen = {};
for (const f of fs.readdirSync(dir).filter(x => /^scancode-.+\.json$/.test(x) && !['scancode-resumen.json', 'scancode-textos.json', 'scancode-propuesta.json'].includes(x))) {
  const pieza = f.slice('scancode-'.length, -'.json'.length);
  const s = new Set();
  for (const file of JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')).files || []) if (exprDe(file)) s.add(exprDe(file));
  resumen[pieza] = [...s].sort();
}
fs.writeFileSync(path.join(dir, 'scancode-resumen.json'), JSON.stringify(resumen, null, 1) + '\n');

// Licencias cubiertas por los textos publicados de cada pieza (rutas licencias/<pieza>/<archivo>)
const cubiertas = {};
for (const file of JSON.parse(fs.readFileSync(path.join(dir, 'scancode-textos.json'), 'utf8')).files || []) {
  const partes = file.path.split('/'); const i = partes.indexOf('licencias');
  const pieza = i >= 0 ? partes[i + 1] : null;
  if (!pieza || !exprDe(file)) continue;
  (cubiertas[pieza] ||= new Set()); for (const c of claves(exprDe(file))) cubiertas[pieza].add(c);
}
const cubre = (p, e) => claves(e).every(c => cubiertas[p] && cubiertas[p].has(c));

const propuesta = { _estado: 'PENDIENTE', _nota: 'Propuesta de tools/scancode.sh: revisar cada PENDIENTE (anadir el texto a notices/<pieza>/pieza.conf o escribir por que no hace falta aviso), quitar _estado y copiarla a notices/scancode-base.json.', piezas: {} };
for (const [p, exprs] of Object.entries(resumen)) propuesta.piezas[p] = Object.fromEntries(exprs.map(e => [e, cubre(p, e) ? 'textos' : 'PENDIENTE']));
fs.writeFileSync(path.join(dir, 'scancode-propuesta.json'), JSON.stringify(propuesta, null, 1) + '\n');

const base = JSON.parse(fs.readFileSync(baseF, 'utf8'));
if (base._estado === 'PENDIENTE' || !base.piezas) {
  console.log('scancode: la base esta PENDIENTE; scancode-propuesta.json es la propuesta (revisarla y copiarla a notices/scancode-base.json)');
  process.exit(estricto === '--estricto' ? 1 : 0);
}
const rojos = [];
for (const [p, exprs] of Object.entries(resumen)) for (const e of exprs) if (!(base.piezas[p] && e in base.piezas[p])) rojos.push(`HALLAZGO NUEVO ${p}: ${e}`);
for (const [p, entradas] of Object.entries(base.piezas)) for (const [e, como] of Object.entries(entradas)) {
  if (typeof como !== 'string' || !como.trim() || como.trim() === 'PENDIENTE') rojos.push(`SIN JUSTIFICAR ${p}: ${e}`);
  else if (como.trim() === 'textos' && !cubre(p, e)) rojos.push(`NO AVISADA ${p}: ${e} (los textos de notices/${p} no la recogen: ${claves(e).filter(c => !(cubiertas[p] && cubiertas[p].has(c))).join(' ')})`);
}
for (const x of rojos) console.log(x);
console.log(`scancode: ${Object.keys(resumen).length} piezas, ${rojos.length} problema(s)`);
process.exit(rojos.length && estricto === '--estricto' ? 1 : 0);
EOF
