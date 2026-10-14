// tools/comun.mjs - lectura de versions.lock, piezas.conf y de los volcados de tools/info-binario.sh.
// Lo usan puertas.mjs, manifiesto.mjs, paridad.mjs, enlazado.mjs y avisos.mjs. Solo Node, sin dependencias.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';

export const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export function leerLock(archivo = path.join(RAIZ, 'versions.lock')) {
  const filas = new Map();
  for (const linea of fs.readFileSync(archivo, 'utf8').split(/\r?\n/)) {
    if (/^\s*(#|$)/.test(linea)) continue;
    const c = linea.trim().split(/\s+/);
    const fila = { pieza: c[0], sistemas: c[1].split(','), tipo: c[2], origen: c[3], ref: c[4], claves: {} };
    for (const kv of c.slice(5)) {
      const i = kv.indexOf(':');
      if (i > 0) fila.claves[kv.slice(0, i)] = kv.slice(i + 1);
    }
    filas.set(fila.pieza, fila);
  }
  return filas;
}

export function leerPiezas(archivo = path.join(RAIZ, 'piezas.conf')) {
  const secciones = {};
  let actual = null;
  for (const linea of fs.readFileSync(archivo, 'utf8').split(/\r?\n/)) {
    if (/^\s*(#|$)/.test(linea)) continue;
    const m = /^\[(.+)\]$/.exec(linea.trim());
    if (m) { actual = m[1]; secciones[actual] = []; continue; }
    if (actual) secciones[actual].push(linea.trim());
  }
  const valor = (clave) => (secciones.global || []).map(l => l.split('=')).find(([k]) => k === clave)?.slice(1).join('=');
  const palabras = (s) => (secciones[s] || []).join(' ').split(/\s+/).filter(Boolean);
  const pares = (s) => (secciones[s] || []).map(l => l.split(/\s+/));
  return { secciones, valor, palabras, pares };
}

// Secciones de configure en orden para cada sistema (igual que tools/piezas.sh).
export function argsConfigure(piezas, sistema) {
  const orden = {
    win: ['configure-entorno-win', 'configure-comun', 'configure-win'],
    'mac-arm64': ['configure-entorno-mac-arm64', 'configure-comun', 'configure-mac', 'configure-mac-arm64'],
    'mac-x86_64': ['configure-entorno-mac-x86_64', 'configure-comun', 'configure-mac', 'configure-mac-x86_64'],
  }[sistema];
  if (!orden) throw new Error('sistema desconocido: ' + sistema);
  return orden.flatMap(s => piezas.secciones[s] || []);
}

export function listaBlancaCodificadores(piezas, sistema) {
  return argsConfigure(piezas, sistema).filter(a => a.startsWith('--enable-encoder='))
    .flatMap(a => a.slice('--enable-encoder='.length).split(','));
}

// «-» y «_» son lo mismo para comparar (configure dice libvpx_vp9, -encoders dice libvpx-vp9).
export const norm = (n) => n.replace(/-/g, '_');
export const casa = (nombre, patron) =>
  new RegExp('^' + norm(patron).replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$').test(norm(nombre));

// Parsers de la salida de ffmpeg
export function parseCodecs(texto) {           // -encoders / -decoders
  const s = new Set();
  for (const l of texto.split(/\r?\n/)) { const m = /^\s[VAS][F.][S.][X.][B.][D.]\s+(\S+)/.exec(l); if (m && m[1] !== '=') s.add(m[1]); }
  return s;
}
export function parseFiltros(texto) {
  const s = new Set();
  for (const l of texto.split(/\r?\n/)) { const m = /^\s[T.][S.][C.]?\s+(\S+)\s+\S*->\S*/.exec(l); if (m) s.add(m[1]); }
  return s;
}
export function parseMuxDemux(texto) {          // -muxers / -demuxers: columnas fijas « DEd nombre»
  const s = new Set();
  for (const l of texto.split(/\r?\n/)) { const m = /^ ([D ])([E ])([d ]) +(\S+)/.exec(l); if (m && (m[1] === 'D' || m[2] === 'E')) for (const n of m[4].split(',')) s.add(n); }
  return s;
}
export function parseProtocolos(texto) {
  const r = { entrada: new Set(), salida: new Set() };
  let modo = null;
  for (const l of texto.split(/\r?\n/)) {
    if (/^Input:/.test(l)) { modo = 'entrada'; continue; }
    if (/^Output:/.test(l)) { modo = 'salida'; continue; }
    const n = l.trim(); if (modo && n && !/:$/.test(n)) r[modo].add(n);
  }
  return r;
}
export function parseLineas(texto, saltar = 0) {
  return new Set(texto.split(/\r?\n/).slice(saltar).map(x => x.trim()).filter(Boolean));
}

export function leerInfo(dir) {
  const leer = (f) => { try { return fs.readFileSync(path.join(dir, f), 'utf8'); } catch { return ''; } };
  return {
    version: leer('version.txt').split(/\r?\n/)[0] || '',
    versionCompleta: leer('version.txt'),
    licencia: leer('licencia.txt'),
    buildconf: leer('buildconf.txt').split(/\r?\n/).filter(Boolean),
    encoders: parseCodecs(leer('encoders.txt')),
    decoders: parseCodecs(leer('decoders.txt')),
    filters: parseFiltros(leer('filters.txt')),
    muxers: parseMuxDemux(leer('muxers.txt')),
    demuxers: parseMuxDemux(leer('demuxers.txt')),
    protocols: parseProtocolos(leer('protocols.txt')),
    bsfs: parseLineas(leer('bsfs.txt'), 1),
    hwaccels: parseLineas(leer('hwaccels.txt'), 1),
    sha256: leer('sha256.txt').trim(),
  };
}

export const sha256 = (archivo) => crypto.createHash('sha256').update(fs.readFileSync(archivo)).digest('hex');
export const sha256Texto = (texto) => crypto.createHash('sha256').update(texto).digest('hex');

// Version visible: <ref de ffmpeg en el lock>-<--extra-version>
export function versionEsperada(lock, piezas) {
  const extra = (piezas.secciones['configure-comun'] || []).find(a => a.startsWith('--extra-version='))?.split('=')[1];
  return `${lock.get('ffmpeg').ref}-${extra}`;
}

// Salida de las puertas: OK / ROJO / NO-MEDIDA, con resumen y codigo de salida.
export function informe(titulo) {
  const filas = [];
  const api = {
    ok: (id, txt) => filas.push(['OK', id, txt]),
    rojo: (id, txt) => filas.push(['ROJO', id, txt]),
    nm: (id, txt) => filas.push(['NO-MEDIDA', id, txt]),
    si: (cond, id, txt, detalle = '') => cond ? api.ok(id, txt) : api.rojo(id, txt + (detalle ? ' — ' + detalle : '')),
    terminar(jsonArchivo) {
      console.log(`\n== ${titulo}`);
      for (const [e, id, t] of filas) console.log(`${e.padEnd(9)} ${id.padEnd(6)} ${t}`);
      const rojos = filas.filter(f => f[0] === 'ROJO').length;
      console.log(`RESUMEN  OK ${filas.filter(f => f[0] === 'OK').length} · ROJO ${rojos} · NO-MEDIDA ${filas.filter(f => f[0] === 'NO-MEDIDA').length}`);
      if (jsonArchivo) fs.writeFileSync(jsonArchivo, JSON.stringify({ titulo, filas }, null, 1));
      if (process.env.GITHUB_STEP_SUMMARY) {
        const md = [`### ${titulo}`, '', '| estado | puerta | detalle |', '|---|---|---|', ...filas.map(([e, id, t]) => `| ${e} | ${id} | ${t.replace(/\|/g, '\\|')} |`), ''];
        fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, md.join('\n') + '\n');
      }
      process.exitCode = rojos ? 1 : 0;
      return rojos;
    },
  };
  return api;
}
