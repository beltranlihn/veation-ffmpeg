// tools/paridad.mjs - Windows y Mac son el MISMO FFmpeg salvo lo propio de cada sistema
// (FFMPEG-PROPIO.md, 2.5.5).
//
//   node tools/paridad.mjs <manifest-win.json> <manifest-mac-arm64.json> [<manifest-mac-x86_64.json>]
//        [--corpus <corpus-win.json> <corpus-mac.json>] [--json f]
//
// Exige:
//   P1  la misma cadena de version en todos (A1 del diseno: «ffmpeg version 8.1.3-veation.N»);
//   P2  las mismas versiones de libavutil, libavcodec... en todos;
//   P3  -buildconf: lo que difiere son exactamente las secciones de configure propias de cada sistema
//       en piezas.conf (configure-entorno-*, configure-win, configure-mac...);
//   P4  codificadores, decodificadores, filtros, muxers, demuxers, protocolos, bsf y hwaccels: toda
//       diferencia casa con expected/paridad-permitida.txt;
//   P5  las dos arquitecturas del Mac, identicas en todo salvo --arch y --enable-neon;
//   P6  (con --corpus) el corpus de la puerta F se decodifica igual en Windows y en el Mac (framemd5).
import fs from 'node:fs';
import path from 'node:path';
import { RAIZ, leerPiezas, argsConfigure, casa, informe } from './comun.mjs';

const args = process.argv.slice(2);
const ic = args.indexOf('--corpus');
const corpus = ic >= 0 ? [args[ic + 1], args[ic + 2]] : null;
const ij = args.indexOf('--json'); const json = ij >= 0 ? args[ij + 1] : null;
const archivos = args.filter((a, i) => !a.startsWith('--') && !(ic >= 0 && (i === ic + 1 || i === ic + 2)) && !(ij >= 0 && i === ij + 1));
if (archivos.length < 2) { console.error('uso: paridad.mjs <manifest-win> <manifest-mac-arm64> [<manifest-mac-x86_64>] [--corpus w m] [--json f]'); process.exit(2); }
const [win, ...macs] = archivos.map(f => JSON.parse(fs.readFileSync(f, 'utf8')));
const piezas = leerPiezas();
const r = informe('Paridad Windows <-> Mac');

const todos = [win, ...macs];
r.si(todos.every(m => m.version === win.version), 'P1', `misma version en todos: «${win.version}»`, todos.map(m => `${m.sistema}=${m.version}`).join(' '));
r.si(todos.every(m => JSON.stringify(m.libav) === JSON.stringify(win.libav)), 'P2', 'mismas versiones de las bibliotecas libav*', todos.map(m => m.sistema + ': ' + m.libav.join(', ')).join(' | '));

// P3: el -buildconf de cada uno es el de su sistema; la parte comun es identica
const comun = piezas.secciones['configure-comun'];
for (const m of macs) {
  const enWin = new Set(win.buildconf.flatMap(l => l.split(/ (?=--)/)));
  const enMac = new Set(m.buildconf.flatMap(l => l.split(/ (?=--)/)));
  const soloWin = [...enWin].filter(x => !enMac.has(x)), soloMac = [...enMac].filter(x => !enWin.has(x));
  const quote = (a) => { const n = a.indexOf('='); if (n < 0) return a; const v = a.slice(n + 1); return a.slice(0, n + 1) + (/[^A-Za-z0-9_\/.+-]/.test(v) ? `'${v}'` : v); };
  const propiasWin = new Set(argsConfigure(piezas, 'win').filter(a => !comun.includes(a)).map(quote));
  const propiasMac = new Set(argsConfigure(piezas, m.sistema === 'mac-x86_64' ? 'mac-x86_64' : 'mac-arm64').filter(a => !comun.includes(a)).map(quote));
  const malas = [...soloWin.filter(x => !propiasWin.has(x)).map(x => 'win:' + x), ...soloMac.filter(x => !propiasMac.has(x)).map(x => 'mac:' + x)];
  r.si(malas.length === 0, 'P3', `-buildconf win/${m.sistema}: solo difieren las opciones propias de cada sistema`, malas.join(' '));
}

// P4: listas
const permitido = { win: {}, mac: {} };
for (const l of fs.readFileSync(path.join(RAIZ, 'expected', 'paridad-permitida.txt'), 'utf8').split(/\r?\n/)) {
  if (/^\s*(#|$)/.test(l)) continue;
  const [cat, lado, ...pat] = l.trim().split(/\s+/);
  (permitido[lado][cat] ||= []).push(...pat);
}
const listas = (m) => ({ encoders: m.encoders, decoders: m.decoders, filters: m.filters, muxers: m.muxers, demuxers: m.demuxers,
  protocols: [...m.protocols.entrada.map(x => 'in:' + x), ...m.protocols.salida.map(x => 'out:' + x)], bsfs: m.bsfs, hwaccels: m.hwaccels });
for (const m of macs) {
  const lw = listas(win), lm = listas(m);
  for (const cat of Object.keys(lw)) {
    const sw = new Set(lw[cat]), sm = new Set(lm[cat]);
    const soloW = [...sw].filter(x => !sm.has(x)), soloM = [...sm].filter(x => !sw.has(x));
    const malasW = soloW.filter(x => !(permitido.win[cat] || []).some(p => casa(x, p)));
    const malasM = soloM.filter(x => !(permitido.mac[cat] || []).some(p => casa(x, p)));
    r.si(!malasW.length && !malasM.length, 'P4', `${cat} win/${m.sistema}: ${soloW.length} solo en win y ${soloM.length} solo en mac, todas permitidas`,
      [...malasW.map(x => 'solo-win:' + x), ...malasM.map(x => 'solo-mac:' + x)].slice(0, 15).join(' '));
  }
}

// P5: arm64 y x86_64 iguales salvo la arquitectura
if (macs.length === 2) {
  const [a, b] = macs; const la = listas(a), lb = listas(b);
  const dif = Object.keys(la).filter(k => JSON.stringify(la[k]) !== JSON.stringify(lb[k]));
  r.si(dif.length === 0, 'P5', 'mac-arm64 y mac-x86_64: mismas listas', 'difieren: ' + dif.join(' '));
  const ba = new Set(a.buildconf.flatMap(l => l.split(/ (?=--)/))), bb = new Set(b.buildconf.flatMap(l => l.split(/ (?=--)/)));
  const d = [...[...ba].filter(x => !bb.has(x)), ...[...bb].filter(x => !ba.has(x))].filter(x => !/^--arch=|^--enable-neon$/.test(x));
  r.si(d.length === 0, 'P5b', 'mac-arm64 y mac-x86_64: -buildconf igual salvo --arch y --enable-neon', d.join(' '));
}

// P6: corpus
if (corpus) {
  const cw = JSON.parse(fs.readFileSync(corpus[0], 'utf8')), cm = JSON.parse(fs.readFileSync(corpus[1], 'utf8'));
  const comunes = Object.keys(cw).filter(k => k in cm);
  const distintos = comunes.filter(k => cw[k] !== cm[k]);
  if (!comunes.length) r.nm('P6', 'el corpus de Windows y el del Mac no tienen formatos en comun');
  else r.si(distintos.length === 0, 'P6', `${comunes.length} formatos del corpus F decodificados igual en Windows y en el Mac`, 'distintos: ' + distintos.join(' '));
}
r.terminar(json);
