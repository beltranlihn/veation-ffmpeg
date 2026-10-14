// tools/manifiesto.mjs - manifiesto de un binario (lo que dice de si mismo + sha256 de los archivos),
// a partir del volcado de tools/info-binario.sh. Lo leen paridad.mjs y avisos.mjs.
//
//   node tools/manifiesto.mjs --sistema <win|mac-arm64|mac-x86_64|mac-universal> --info <dir>
//        --dir <dir con los binarios> --salida <manifest-<sistema>.json>
//
// buildconf_sha256 = sha256 de buildconf.txt de info-binario.sh, es decir, de las lineas que siguen a
// «configuration:» en «ffmpeg -hide_banner -buildconf», sin CR, sin espacios al principio ni al final,
// sin lineas vacias, cada una terminada en «\n». Es la misma normalizacion que tiene que usar VEATION
// (scripts/comprobar-ffmpeg.mjs) y coincide con el sha256 de expected/buildconf-<sistema>.txt.
import fs from 'node:fs';
import path from 'node:path';
import { leerInfo, sha256 } from './comun.mjs';

const arg = (k) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : null; };
const sistema = arg('--sistema'), dirInfo = arg('--info'), dir = arg('--dir'), salida = arg('--salida');
if (!sistema || !dirInfo || !dir || !salida) { console.error('uso: manifiesto.mjs --sistema s --info d --dir d --salida f'); process.exit(2); }

const info = leerInfo(dirInfo);
const binarios = {};
for (const f of fs.readdirSync(dir).sort()) {
  const p = path.join(dir, f);
  if (fs.statSync(p).isFile() && /^(ffmpeg|ffprobe)(_g)?(\.exe)?$/.test(f)) binarios[f] = sha256(p);
}
const version = info.versionCompleta.split(/\r?\n/);
const m = {
  sistema,
  version: info.version.split(/\s+/).slice(0, 3).join(' '),
  libav: version.filter(l => /^lib(av|sw)\w+\s/.test(l)).map(l => l.replace(/\s+/g, ' ').trim()),
  buildconf: info.buildconf,
  buildconf_sha256: sha256(path.join(dirInfo, 'buildconf.txt')),
  encoders: [...info.encoders].sort(),
  decoders: [...info.decoders].sort(),
  filters: [...info.filters].sort(),
  muxers: [...info.muxers].sort(),
  demuxers: [...info.demuxers].sort(),
  protocols: { entrada: [...info.protocols.entrada].sort(), salida: [...info.protocols.salida].sort() },
  bsfs: [...info.bsfs].sort(),
  hwaccels: [...info.hwaccels].sort(),
  binarios,
};
fs.writeFileSync(salida, JSON.stringify(m, null, 1) + '\n');
console.log(`manifiesto ${sistema}: ${m.version} · ${m.encoders.length} codificadores · ${m.decoders.length} decodificadores · buildconf ${m.buildconf_sha256.slice(0, 12)}`);
