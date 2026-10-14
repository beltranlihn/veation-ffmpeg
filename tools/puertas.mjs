// tools/puertas.mjs - puertas ESTATICAS de un binario (FFMPEG-PROPIO.md, 2.5.2, 3.4 y 5.6 A, C, H).
// Lee el volcado de tools/info-binario.sh; no ejecuta nada. Las puertas de COMPORTAMIENTO (codificar,
// decodificar, enlazado real en el sistema) estan en tools/ff-checklist.mjs.
//
//   node tools/puertas.mjs --sistema win|mac-arm64|mac-x86_64 --info <dir>
//        [--binario <ffmpeg>] [--configure-out <configure.out>] [--json <salida.json>]
//
// Sale con 1 si alguna puerta esta en ROJO.
import fs from 'node:fs';
import path from 'node:path';
import { RAIZ, leerLock, leerPiezas, leerInfo, listaBlancaCodificadores, norm, casa, versionEsperada, informe } from './comun.mjs';

const arg = (k) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : null; };
const sistema = arg('--sistema'); const dirInfo = arg('--info');
if (!sistema || !dirInfo) { console.error('uso: puertas.mjs --sistema <s> --info <dir> [--binario f] [--configure-out f] [--json f]'); process.exit(2); }
const familia = sistema.startsWith('mac') ? 'mac' : 'win';

const lock = leerLock(); const piezas = leerPiezas(); const info = leerInfo(dirInfo);
const r = informe(`Puertas estaticas ${sistema}`);

// A1 version
const esperada = `ffmpeg version ${versionEsperada(lock, piezas)}`;
r.si(info.version.split(/\s+/).slice(0, 3).join(' ') === esperada, 'A1', `-version = «${esperada}»`, `dice «${info.version.slice(0, 80)}»`);
// A2 licencia
r.si(/version 3 of the License, or/.test(info.licencia), 'A2', '-L declara GPL version 3 or later');
// A3 / A4 buildconf
const bc = info.buildconf.join('\n');
const prohibidas = piezas.palabras('buildconf-prohibido').filter(p => bc.includes(p));
r.si(prohibidas.length === 0, 'A3', '-buildconf sin piezas prohibidas', prohibidas.join(' '));
const faltan = piezas.palabras('buildconf-obligatorio').filter(p => !info.buildconf.some(l => l.split(' ').includes(p)));
r.si(faltan.length === 0, 'A4', '-buildconf con las opciones obligatorias', 'faltan ' + faltan.join(' '));
// BC: -buildconf exacto
const esperado = fs.readFileSync(path.join(RAIZ, 'expected', `buildconf-${sistema}.txt`), 'utf8').split(/\r?\n/).filter(Boolean);
const iguales = esperado.length === info.buildconf.length && esperado.every((l, i) => l === info.buildconf[i]);
if (!iguales) {
  const sobran = info.buildconf.filter(l => !esperado.includes(l)), faltanL = esperado.filter(l => !info.buildconf.includes(l));
  r.rojo('BC', `-buildconf != expected/buildconf-${sistema}.txt — sobran: ${sobran.join(' ') || '-'} · faltan: ${faltanL.join(' ') || '-'}${!sobran.length && !faltanL.length ? ' · (mismo contenido, distinto orden)' : ''}`);
} else r.ok('BC', `-buildconf identico a expected/buildconf-${sistema}.txt (${esperado.length} lineas)`);

// B: lista blanca EXACTA de codificadores
const blanca = listaBlancaCodificadores(piezas, sistema);
const fuera = [...info.encoders].filter(e => !blanca.some(p => casa(e, p)));
r.si(fuera.length === 0, 'B1', 'ningun codificador fuera de la lista blanca', 'fuera: ' + fuera.join(' '));
const ausentes = blanca.filter(p => !p.includes('*')).filter(p => ![...info.encoders].some(e => norm(e) === norm(p)));
r.si(ausentes.length === 0, 'B2', `estan los ${blanca.filter(p => !p.includes('*')).length} codificadores con nombre de la lista blanca`, 'faltan: ' + ausentes.join(' '));
const pcm = [...info.encoders].filter(e => e.startsWith('pcm_'));
r.si(pcm.length >= 20, 'B3', `codificadores pcm_* presentes (${pcm.length})`);
// hwaccels
const hw = piezas.palabras(`hwaccels-${familia}`).filter(h => !info.hwaccels.has(h));
r.si(hw.length === 0, 'B4', 'aceleracion por hardware: ' + piezas.palabras(`hwaccels-${familia}`).join(' '), 'faltan ' + hw.join(' '));

// C: lo prohibido ausente
const encP = piezas.palabras('codificadores-prohibidos').filter(p => [...info.encoders].some(e => norm(e) === norm(p)));
r.si(encP.length === 0, 'C1-3', 'codificadores prohibidos ausentes (ProRes propio, aac, Dolby/DTS, sin uso)', 'PRESENTES: ' + encP.join(' '));
const decP = piezas.palabras('decodificadores-prohibidos').filter(p => [...info.decoders].some(d => norm(d) === norm(p)));
r.si(decP.length === 0, 'C5', 'decodificadores prohibidos ausentes (vvc, vvc_qsv)', 'PRESENTES: ' + decP.join(' '));
const proto = piezas.palabras('protocolos-prohibidos').filter(p => info.protocols.entrada.has(p) || info.protocols.salida.has(p));
r.si(proto.length === 0, 'C4', 'protocolos de red ausentes', 'PRESENTES: ' + proto.join(' '));
r.si(info.protocols.entrada.has('file') && info.protocols.entrada.has('pipe'), 'C4b', 'protocolos file y pipe presentes');

// H: driver NVIDIA minimo (cadena de nvenc.c segun las cabeceras elegidas)
if (familia === 'win') {
  const bin = arg('--binario');
  if (!bin) r.nm('H', 'sin --binario no se busca la cadena del driver NVENC');
  else {
    const minimo = piezas.valor('nvenc-min-driver');
    const contenido = fs.readFileSync(bin).toString('latin1');
    const otros = ['531.61', '551.76', '570.0'].filter(v => v !== minimo && contenido.includes('\0' + v + '\0'));
    r.si(contenido.includes('\0' + minimo + '\0'), 'H', `el binario lleva la cadena del driver NVENC minimo ${minimo}`, otros.length ? 'lleva ' + otros.join(' ') : 'no aparece');
  }
}

// AV: avisos de configure
const confOut = arg('--configure-out');
if (confOut) {
  const texto = fs.readFileSync(confOut, 'utf8');
  const noCasa = texto.split(/\r?\n/).filter(l => /did not match anything/.test(l));
  r.si(noCasa.length === 0, 'AV1', 'configure: ninguna opcion «did not match anything»', noCasa.join(' | '));
  let permitidos = [];
  try { permitidos = fs.readFileSync(path.join(RAIZ, 'expected', 'avisos-configure.txt'), 'utf8').split(/\r?\n/).filter(l => l && !l.startsWith('#')); } catch {}
  const avisos = texto.split(/\r?\n/).filter(l => /^WARNING:/.test(l) && !permitidos.some(p => l.includes(p)));
  r.si(avisos.length === 0, 'AV2', 'configure: ningun WARNING fuera de expected/avisos-configure.txt', avisos.join(' | '));
} else r.nm('AV', 'sin --configure-out no se miran los avisos de configure');

r.terminar(arg('--json'));
