// tools/corpus.mjs - decodifica un corpus YA fabricado (el que dejo ff-checklist --corpus-dir en el
// runner de Windows) y escribe el framemd5 de cada archivo, igual que la puerta F. Sirve para la paridad
// P6: el binario del Mac tiene que decodificar los MISMOS archivos exactamente igual que el de Windows.
//
//   node tools/corpus.mjs <ffmpeg> <dir del corpus> --salida <corpus-mac-<arch>.json>
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [FF, DIR] = process.argv.slice(2);
const i = process.argv.indexOf('--salida'); const salida = i > 0 ? process.argv[i + 1] : null;
if (!FF || !DIR || !salida) { console.error('uso: corpus.mjs <ffmpeg> <dir> --salida <json>'); process.exit(2); }
const res = {};
for (const f of fs.readdirSync(DIR).sort()) {
  const m = /^c-(.+)\.[^.]+$/.exec(f); if (!m) continue;
  const extra = m[1] === 'vp9a' ? ['-c:v', 'libvpx-vp9'] : [];
  /* modo reproducible, el mismo que usa ff-checklist para --corpus-salida: entre arquitecturas, la IDCT y
     la ICT por defecto (SIMD de cada una) no dan los mismos bits (ff-checklist.mjs, puerta F) */
  const r = spawnSync(FF, ['-hide_banner', '-loglevel', 'error', '-flags', '+bitexact', '-idct', 'simple', ...extra, '-i', path.join(DIR, f), '-map', '0', '-f', 'framemd5', '-'], { encoding: 'latin1', maxBuffer: 1 << 28 });
  if (r.status === 0) res[m[1]] = r.stdout.split(/\r?\n/).filter(l => l && l[0] !== '#').join('\n');
  console.log(`${r.status === 0 ? 'ok ' : 'NO '} ${f}`);
}
fs.writeFileSync(salida, JSON.stringify(res, null, 1));
