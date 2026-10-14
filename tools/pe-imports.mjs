// tools/pe-imports.mjs - DLL que importa un ejecutable PE de 64 bits (normales y de carga diferida).
// Origen: scratchpad/crit-pe-imports.mjs de VEATION (critica del diseno, punto 11).
//
//   node tools/pe-imports.mjs <exe> [--prohibir a.dll,b.dll] [--lista-sistema <archivo>] [--system32] [--json]
//
//   --prohibir        estas DLL no pueden aparecer como importacion ESTATICA (ni diferida). Media
//                     Foundation (mfplat, mf, mfreadwrite, evr) se carga en tiempo de ejecucion: si se
//                     importara, ffmpeg.exe no arrancaria en las ediciones N de Windows.
//   --lista-sistema   cada DLL importada tiene que estar en la lista (o ser api-ms-win-* / ext-ms-*).
//                     Es lo que se puede medir en Linux; en un runner Windows, --system32 mira el disco.
//   --system32        cada DLL importada tiene que existir en %SystemRoot%\System32.
// Sale con 1 si algo no se cumple.
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const exe = args[0];
if (!exe) { console.error('uso: pe-imports.mjs <exe> [--prohibir x,y] [--lista-sistema f] [--system32] [--json]'); process.exit(2); }
const opt = (k) => { const i = args.indexOf(k); return i > 0 ? args[i + 1] : null; };

function leerImportaciones(archivo) {
  const b = fs.readFileSync(archivo);
  if (b.toString('latin1', 0, 2) !== 'MZ') throw new Error('no es un PE (sin MZ)');
  const pe = b.readUInt32LE(0x3c);
  if (b.toString('latin1', pe, pe + 4) !== 'PE\0\0') throw new Error('no es un PE (sin firma PE)');
  const nsec = b.readUInt16LE(pe + 6);
  const optSize = b.readUInt16LE(pe + 20);
  const opt0 = pe + 24;
  const magic = b.readUInt16LE(opt0);
  const ddBase = opt0 + (magic === 0x20b ? 112 : 96);
  const dd = (i) => [b.readUInt32LE(ddBase + i * 8), b.readUInt32LE(ddBase + i * 8 + 4)];
  const secs = [];
  for (let i = 0; i < nsec; i++) {
    const s = opt0 + optSize + i * 40;
    secs.push({ va: b.readUInt32LE(s + 12), vs: b.readUInt32LE(s + 8), rs: b.readUInt32LE(s + 16), raw: b.readUInt32LE(s + 20) });
  }
  const off = (rva) => { for (const s of secs) if (rva >= s.va && rva < s.va + Math.max(s.vs, s.rs, 1)) return rva - s.va + s.raw; return -1; };
  const cstr = (o) => { let e = o; while (b[e]) e++; return b.toString('latin1', o, e); };
  const r = { estaticas: [], diferidas: [], pe64: magic === 0x20b };
  const [irva] = dd(1);
  if (irva) for (let o = off(irva); o > 0; o += 20) { const n = b.readUInt32LE(o + 12); if (!n) break; r.estaticas.push(cstr(off(n))); }
  const [drva] = dd(13);
  if (drva) for (let o = off(drva); o > 0; o += 32) { const n = b.readUInt32LE(o + 4); if (!n) break; r.diferidas.push(cstr(off(n))); }
  r.subsistema = b.readUInt16LE(opt0 + 68);
  r.minOS = `${b.readUInt16LE(opt0 + 40)}.${b.readUInt16LE(opt0 + 42)}`;
  return r;
}

const imp = leerImportaciones(exe);
const todas = [...imp.estaticas, ...imp.diferidas];
const fallos = [];
if (!imp.pe64) fallos.push('no es un PE de 64 bits');

const prohibidas = (opt('--prohibir') || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
for (const d of todas) if (prohibidas.includes(d.toLowerCase())) fallos.push(`importa ${d} (prohibida: se carga en tiempo de ejecucion)`);

const sistemaApi = (d) => /^(api-ms-win-|ext-ms-)/i.test(d);
const lista = opt('--lista-sistema');
if (lista) {
  const ok = new Set(fs.readFileSync(lista, 'utf8').split(/\r?\n/).map(l => l.replace(/#.*/, '').trim().toLowerCase()).filter(Boolean));
  for (const d of todas) if (!sistemaApi(d) && !ok.has(d.toLowerCase())) fallos.push(`importa ${d}, que no esta en ${path.basename(lista)}`);
}
if (args.includes('--system32')) {
  const sys = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32');
  for (const d of todas) if (!sistemaApi(d) && !fs.existsSync(path.join(sys, d))) fallos.push(`importa ${d}, que no esta en ${sys}`);
}

if (args.includes('--json')) console.log(JSON.stringify({ ...imp, fallos }, null, 1));
else {
  console.log(`${path.basename(exe)}: ${imp.estaticas.length} DLL estaticas, ${imp.diferidas.length} diferidas`);
  console.log('  estaticas: ' + imp.estaticas.join(' '));
  if (imp.diferidas.length) console.log('  diferidas: ' + imp.diferidas.join(' '));
  for (const f of fallos) console.log('  ROJO: ' + f);
}
process.exit(fallos.length ? 1 : 0);
