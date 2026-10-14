// tools/enlazado.mjs - lo que el enlazador ABRIO de verdad al producir ffmpeg y ffprobe
// (FFMPEG-PROPIO.md, 2.5.2 «Enlazado real»). Lee la traza del reenlazado (-Wl,--trace con GNU ld en
// Windows, -Wl,-t con el ld de Apple), que build.sh / mac/ffmpeg.sh guardan en enlazado.log.
//
//   node tools/enlazado.mjs --sistema win|mac --log <enlazado.log> --salida <linked-<sistema>.txt> [--json f]
//
// Clasifica cada archivo por su ruta (piezas.conf, [enlazado-rutas-<sistema>]):
//   prefijo      biblioteca propia: su nombre tiene que estar en [enlazado] y la pieza en el lock
//   runtime      toolchain o SDK (libgcc, libstdc++, CRT de mingw-w64, winpthreads / libSystem, frameworks)
//   shim         el libstdc++.tbd del Mac que apunta a libc++
//   compilacion  objetos y bibliotecas internas de FFmpeg (libavcodec.a...), ruta relativa o del arbol
// Cualquier otra cosa (Homebrew, /usr/local, una biblioteca sin fila) pone la puerta en ROJO.
// Ademas exige que se hayan abierto TODAS las bibliotecas del sistema en [enlazado] que tienen fila en el
// lock para ese sistema: una pieza del lock que no se enlaza es una pieza que sobra (o una que falta).
import fs from 'node:fs';
import { leerLock, leerPiezas, informe } from './comun.mjs';

const arg = (k) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : null; };
const sistema = arg('--sistema'), log = arg('--log'), salida = arg('--salida');
if (!['win', 'mac'].includes(sistema) || !log || !salida) { console.error('uso: enlazado.mjs --sistema win|mac --log f --salida f'); process.exit(2); }

const lock = leerLock(); const piezas = leerPiezas();
const mapa = new Map(piezas.pares('enlazado').map(([a, p]) => [a, p]));
const rutas = piezas.pares(`enlazado-rutas-${sistema}`).map(([tipo, prefijo]) => ({ tipo, prefijo }));
const r = informe(`Enlazado real ${sistema}`);

// Extrae rutas de archivo de cada linea de la traza: «/ruta/lib.a(miembro.o)», «(/ruta/lib.a)miembro.o»,
// «/ruta/objeto.o», «libavcodec/libavcodec.a», «/ruta/libSystem.tbd», «-lfoo (/ruta/libfoo.a)».
const archivos = new Set();
for (const linea of fs.readFileSync(log, 'utf8').split(/\r?\n/)) {
  for (const m of linea.matchAll(/(?:^|[\s(])((?:\/|\.{0,2}\/?[A-Za-z0-9_.+-]+\/)[^\s()]*?\.(?:a|o|obj|tbd|dylib|lib|dll\.a))(?=$|[\s()])/g)) archivos.add(m[1]);
}
if (!archivos.size) { r.rojo('L0', `la traza ${log} no tiene ningun archivo: ¿se reenlazo con traza?`); r.terminar(arg('--json')); process.exit(); }

const filas = [];
const usadas = new Set();
for (const f of [...archivos].sort()) {
  const ruta = rutas.find(x => f.startsWith(x.prefijo));
  let tipo = ruta ? ruta.tipo : (f.startsWith('/') ? 'FUERA' : 'compilacion');
  let pieza = '';
  if (tipo === 'prefijo') {
    const base = f.split('/').pop();
    if (/\.o(bj)?$/.test(base)) { tipo = 'FUERA'; }
    else if (!mapa.has(base)) tipo = 'SIN-FILA';
    else {
      pieza = mapa.get(base);
      const fila = lock.get(pieza);
      if (!fila || !fila.sistemas.includes(sistema)) tipo = 'SIN-LOCK';
      else usadas.add(pieza);
    }
  }
  filas.push([tipo, pieza, f]);
}
fs.writeFileSync(salida, filas.map(x => x.join('\t')).join('\n') + '\n');

const malas = filas.filter(([t]) => ['FUERA', 'SIN-FILA', 'SIN-LOCK'].includes(t));
r.si(malas.length === 0, 'L1', `cada archivo enlazado es de una pieza del lock, del runtime o de FFmpeg (${filas.length} archivos)`,
  malas.map(([t, , f]) => `${t}:${f}`).slice(0, 12).join(' '));
// Bibliotecas del lock para este sistema que deberian haberse abierto desde el prefijo
const esperadas = [...new Set([...mapa.values()])].filter(p => lock.get(p)?.sistemas.includes(sistema));
const noUsadas = esperadas.filter(p => !usadas.has(p));
r.si(noUsadas.length === 0, 'L2', `se enlazan todas las bibliotecas propias del lock (${esperadas.length})`, 'no se abrieron: ' + noUsadas.join(' '));
const runtime = filas.filter(([t]) => t === 'runtime').map(([, , f]) => f.split('/').pop());
if (sistema === 'win') {
  // Lo que se enlace del runtime tiene que constar en FFMPEG-NOTICES.txt (avisos.mjs lo cruza con esto).
  for (const [nombre, re] of [['libstdc++', /^libstdc\+\+\.a$/], ['libgcc', /^libgcc(_eh)?\.a$/], ['winpthreads', /^lib(win)?pthread\.a$/], ['CRT de mingw-w64', /^libmingwex\.a$/]]) {
    r.si(runtime.some(x => re.test(x)), 'L3', `runtime del toolchain enlazado: ${nombre}`);
  }
} else {
  // ld puede escribir la ruta del enlace simbolico o la del libc++.tbd del SDK al que apunta.
  r.si(filas.some(([t]) => t === 'shim') || runtime.includes('libc++.tbd'), 'L3', 'snappy pide -lstdc++ y se resuelve con libc++ del sistema (shim)');
}
r.terminar(arg('--json'));
