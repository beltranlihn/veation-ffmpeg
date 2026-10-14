// tools/avisos.mjs - avisos y manifiesto de una release (FFMPEG-PROPIO.md, 4.3).
//
// Tres fases, en este orden dentro del job «paquete»:
//
//   node tools/avisos.mjs textos --fuentes <dir fuentes> --salida <out/avisos> [--estricto]
//       Extrae del FUENTE EXACTO de cada pieza (fuentes/ + MANIFIESTO.tsv) los textos de licencia que
//       lista notices/<pieza>/pieza.conf, y los compara con notices/<pieza>/REVISADO (sha256 revisados a
//       mano). Deja out/avisos/licencias/<pieza>/... (que tambien van al paquete de fuente) y
//       out/avisos/revision.txt (los sha256 de hoy, para copiar a REVISADO tras leerlos).
//       --estricto (release): falla si queda algun PENDIENTE o un texto ya revisado cambio.
//
//   node tools/avisos.mjs notices --avisos <out/avisos> --manifiestos <dir> --fuente <tar.xz o .part00>
//        --salida <out/release>
//       FFMPEG-NOTICES.txt (cabecera con la build, el sha256 de cada binario y del fuente; una ficha por
//       componente enlazado; los textos LITERALES) y SOURCE.txt.
//
//   node tools/avisos.mjs manifiesto --release <out/release> --manifiestos <dir> --notas <out/NOTAS.md>
//       manifest.json (lo que fija VEATION en vendor/ffmpeg/ffmpeg.lock.json), SHA256SUMS y las notas.
//
// Los manifiestos por sistema (manifest-win.json, manifest-mac-arm64.json, manifest-mac-x86_64.json,
// manifest-mac-universal.json) los escribe tools/manifiesto.mjs en cada job.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { RAIZ, leerLock, leerPiezas, sha256, sha256Texto, versionEsperada } from './comun.mjs';

const [fase, ...resto] = process.argv.slice(2);
const arg = (k) => { const i = resto.indexOf(k); return i >= 0 ? resto[i + 1] : null; };
const lock = leerLock(); const piezas = leerPiezas();
const VERSION = versionEsperada(lock, piezas);
const REPO = process.env.GITHUB_REPOSITORY || 'beltranlihn/veation-ffmpeg';
const TAG = `v${VERSION}`;
const URL_RELEASE = `https://github.com/${REPO}/releases/tag/${TAG}`;
const morir = (m) => { console.error('avisos: ' + m); process.exit(1); };

function confPieza(p) {
  const f = path.join(RAIZ, 'notices', p, 'pieza.conf');
  if (!fs.existsSync(f)) return null;
  const c = {}; for (const l of fs.readFileSync(f, 'utf8').split(/\r?\n/)) { const i = l.indexOf('='); if (i > 0 && !l.startsWith('#')) c[l.slice(0, i)] = l.slice(i + 1); }
  c.textos = (c.textos || '').split(/\s+/).filter(Boolean);
  return c;
}
function revisado(p) {
  const m = new Map(); const f = path.join(RAIZ, 'notices', p, 'REVISADO');
  if (fs.existsSync(f)) for (const l of fs.readFileSync(f, 'utf8').split(/\r?\n/)) { if (!l || l.startsWith('#')) continue; const [t, s] = l.trim().split(/\s+/); m.set(t, s); }
  return m;
}
// Piezas con avisos: las enlazadas (rol fuente) y el runtime del toolchain (mingw-w64, gcc).
const piezasConAvisos = () => [...lock.values()].filter(f => (f.claves.rol === 'fuente' || ['mingw-w64', 'gcc'].includes(f.pieza)) && confPieza(f.pieza)).map(f => f.pieza);

if (fase === 'textos') {
  const fuentes = arg('--fuentes'), salida = arg('--salida'), estricto = resto.includes('--estricto');
  if (!fuentes || !salida) morir('uso: textos --fuentes d --salida d [--estricto]');
  const manifiesto = new Map(fs.readFileSync(path.join(fuentes, 'MANIFIESTO.tsv'), 'utf8').split(/\r?\n/).slice(1).filter(Boolean).map(l => l.split('\t')).map(c => [c[0], c]));
  const lineasRevision = []; const problemas = []; let pendientes = 0;
  for (const p of piezasConAvisos()) {
    const conf = confPieza(p), rev = revisado(p), fila = manifiesto.get(p);
    if (!fila) { problemas.push(`${p}: no esta en ${fuentes}/MANIFIESTO.tsv`); continue; }
    const archivo = path.join(fuentes, fila[5]);
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vf-avisos-'));
    const rutas = conf.textos.map(t => t.split('#')[0]);
    // GNU tar; --force-local: una ruta con «:» (C:/... en Windows) no es un host remoto. Barras normales
    // para que tambien funcione con el tar de Git Bash al probar en Windows.
    const posix = (p) => p.split(path.sep).join('/');
    const r = spawnSync('tar', ['--force-local', '-xf', posix(archivo), '-C', posix(tmp), '--strip-components=1', '--wildcards', '--no-wildcards-match-slash', ...rutas.map(x => '*/' + x)], { encoding: 'utf8', timeout: 600000 });
    if (r.status !== 0) { problemas.push(`${p}: no se pudieron extraer ${rutas.join(' ')} de ${fila[5]}: ${r.stderr.trim().split('\n').pop()}`); continue; }
    lineasRevision.push(`== notices/${p}/REVISADO (${fila[1]})`);
    for (const t of conf.textos) {
      const [ruta, modo] = t.split('#');
      let texto = fs.readFileSync(path.join(tmp, ruta), 'utf8');
      if (modo === 'cabecera') { const m = /\/\*[\s\S]*?\*\//.exec(texto); if (!m) { problemas.push(`${p}: ${ruta} no tiene comentario de cabecera`); continue; } texto = m[0] + '\n'; }
      const destino = path.join(salida, 'licencias', p, ruta.replace(/\//g, '__') + (modo ? '.' + modo : ''));
      fs.mkdirSync(path.dirname(destino), { recursive: true }); fs.writeFileSync(destino, texto);
      const s = sha256Texto(texto);
      lineasRevision.push(`${t} ${s}`);
      const esperado = rev.get(t);
      if (!esperado || esperado === 'PENDIENTE') pendientes++;
      else if (esperado !== s) problemas.push(`${p}: el texto ${t} CAMBIO desde la ultima revision (revisado ${esperado.slice(0, 12)}, hoy ${s.slice(0, 12)})`);
    }
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  fs.mkdirSync(salida, { recursive: true });
  fs.writeFileSync(path.join(salida, 'revision.txt'), lineasRevision.join('\n') + '\n');
  for (const x of problemas) console.error('ROJO: ' + x);
  console.log(`avisos textos: ${piezasConAvisos().length} piezas, ${pendientes} texto(s) sin revisar, ${problemas.length} problema(s)`);
  if (problemas.length || (estricto && pendientes)) morir(estricto && pendientes ? `${pendientes} texto(s) de licencia sin revisar (notices/*/REVISADO): una release no sale sin revisarlos` : 'hay problemas');
  process.exit(0);
}

const leerManifiestos = (dir) => {
  const m = {}; for (const f of fs.readdirSync(dir)) { const x = /^manifest-(.+)\.json$/.exec(f); if (x) m[x[1]] = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); }
  for (const s of ['win', 'mac-arm64', 'mac-x86_64', 'mac-universal']) if (!m[s]) morir(`falta manifest-${s}.json en ${dir}`);
  return m;
};
const partesFuente = (f) => {
  const dir = path.dirname(f), base = path.basename(f).replace(/\.part\d+$/, '');
  const partes = fs.readdirSync(dir).filter(x => x === base || x.startsWith(base + '.part')).sort();
  return { base, partes, dir };
};

if (fase === 'notices') {
  const avisos = arg('--avisos'), dirM = arg('--manifiestos'), fuente = arg('--fuente'), salida = arg('--salida');
  if (!avisos || !dirM || !fuente || !salida) morir('uso: notices --avisos d --manifiestos d --fuente f --salida d');
  const M = leerManifiestos(dirM);
  const { base, partes, dir } = partesFuente(fuente);
  const shaFuente = partes.length === 1 ? sha256(path.join(dir, partes[0])) : null;
  // Si va partido, el sha256 de cada parte (y el del archivo entero, que comprueba verificar-fuente).
  const shaEntero = arg('--sha-entero') || shaFuente;
  const lineasFuente = partes.length === 1 ? [`  ${base}  SHA-256 ${shaFuente}`]
    : [`  ${base}  SHA-256 ${shaEntero} (published in ${partes.length} parts; join them in order with «cat»)`, ...partes.map(p => `    ${p}  SHA-256 ${sha256(path.join(dir, p))}`)];
  const W = M.win.binarios, U = M['mac-universal'].binarios;
  const L = [];
  L.push(`FFmpeg ${VERSION} - third-party notices`, '='.repeat(40 + VERSION.length), '');
  L.push('This file accompanies the FFmpeg program built by Alma Digital Studio for VEATION. FFmpeg is a');
  L.push('separate program, run by VEATION as an external process. FFmpeg is not owned by Alma Digital');
  L.push('Studio; FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.', '');
  L.push(`Build:    FFmpeg ${VERSION}, built from the unmodified upstream FFmpeg ${lock.get('ffmpeg').ref} release`);
  L.push(`          (${lock.get('ffmpeg').origen}), the same version on Windows and macOS.`);
  L.push(`Windows:  ffmpeg.exe   SHA-256 ${W['ffmpeg.exe']}`, `          ffprobe.exe  SHA-256 ${W['ffprobe.exe']}`);
  L.push(`macOS:    ffmpeg       SHA-256 ${U.ffmpeg} (universal: arm64 + x86_64, macOS ${piezas.valor('macos-min')} or later)`, `          ffprobe      SHA-256 ${U.ffprobe}`);
  L.push('License:  GNU General Public License, version 3 or later (configured with --enable-gpl', '          --enable-version3; no non-free components).', '');
  L.push('Complete corresponding source code (FFmpeg, every library linked into these builds, the', 'toolchain runtime, the build scripts and any patches):', `  ${URL_RELEASE}`, ...lineasFuente, '');
  L.push('Components', '----------');
  const lista = piezasConAvisos();
  lista.forEach((p, i) => {
    const f = lock.get(p), c = confPieza(p);
    const sis = f.sistemas.map(s => s === 'win' ? 'Windows' : 'macOS').join(' and ');
    L.push(`${String(i + 1).padStart(2)}. ${c.nombre} ${f.ref}`, `    Source:   ${f.origen}${f.claves.commit && f.claves.commit !== 'PENDIENTE' && f.tipo === 'git' ? ' @ ' + f.claves.commit : ''}`, `    License:  ${c.licencia}`, `    Used on:  ${sis}`);
  });
  L.push('', 'On macOS the build also uses the system zlib, bzip2 and iconv, and Apple VideoToolbox and', 'AudioToolbox (system libraries, not distributed with VEATION).', '');
  L.push('Full license texts and notices', '------------------------------', '');
  for (const p of lista) {
    const c = confPieza(p);
    for (const t of c.textos) {
      const [ruta, modo] = t.split('#');
      const f = path.join(avisos, 'licencias', p, ruta.replace(/\//g, '__') + (modo ? '.' + modo : ''));
      if (!fs.existsSync(f)) morir(`falta el texto ${f}: ejecutar antes «avisos.mjs textos»`);
      L.push(`======== ${c.nombre}: ${ruta}${modo ? ' (header comment)' : ''} ========`, '', fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').trimEnd(), '');
    }
  }
  fs.mkdirSync(salida, { recursive: true });
  fs.writeFileSync(path.join(salida, 'FFMPEG-NOTICES.txt'), L.join('\n') + '\n');
  fs.writeFileSync(path.join(salida, 'SOURCE.txt'), [
    `FFmpeg ${VERSION} is licensed under the GNU General Public License, version 3 or later`,
    '(see COPYING.GPLv3 next to this file). Built by Alma Digital Studio.',
    'Complete corresponding source code (FFmpeg, every linked library, build scripts, patches):',
    URL_RELEASE, ...lineasFuente.map(l => l.trim())].join('\n') + '\n');
  console.log(`avisos notices: FFMPEG-NOTICES.txt (${lista.length} componentes) y SOURCE.txt en ${salida}`);
  process.exit(0);
}

if (fase === 'manifiesto') {
  const rel = arg('--release'), dirM = arg('--manifiestos'), notas = arg('--notas');
  if (!rel || !dirM) morir('uso: manifiesto --release d --manifiestos d [--notas f]');
  const M = leerManifiestos(dirM);
  const assets = {};
  for (const f of fs.readdirSync(rel).sort()) if (fs.statSync(path.join(rel, f)).isFile() && !['manifest.json', 'SHA256SUMS'].includes(f)) assets[f] = sha256(path.join(rel, f));
  const fuente = Object.keys(assets).filter(a => /-source\.tar\.xz(\.part\d+)?$/.test(a));
  const nombre = (s) => Object.keys(assets).find(a => a === `veation-ffmpeg-${VERSION}-${s}.zip`);
  const manifest = {
    version: VERSION, tag: TAG, repo: REPO,
    ffmpeg_commit: lock.get('ffmpeg').claves.commit,
    ffmpeg_tarball_sha256: lock.get('ffmpeg').claves.sha256,
    nvenc_min_driver: piezas.valor('nvenc-min-driver'),
    nvenc_cabeceras: piezas.valor('nvenc-cabeceras'),
    macos_min: piezas.valor('macos-min'),
    assets,
    win: { asset: nombre('win-x64'), ffmpeg_sha256: M.win.binarios['ffmpeg.exe'], ffprobe_sha256: M.win.binarios['ffprobe.exe'], buildconf_sha256: M.win.buildconf_sha256 },
    mac: { asset: nombre('mac-universal'), arquitecturas: ['arm64', 'x86_64'], ffmpeg_sha256: M['mac-universal'].binarios.ffmpeg, ffprobe_sha256: M['mac-universal'].binarios.ffprobe,
           buildconf_sha256: { arm64: M['mac-arm64'].buildconf_sha256, x86_64: M['mac-x86_64'].buildconf_sha256 },
           ffmpeg_sha256_por_arquitectura: { arm64: M['mac-arm64'].binarios.ffmpeg, x86_64: M['mac-x86_64'].binarios.ffmpeg } },
    source: { asset: fuente, sha256: Object.fromEntries(fuente.map(a => [a, assets[a]])), url: URL_RELEASE },
    lock: Object.fromEntries([...lock.values()].filter(f => ['fuente', 'toolchain'].includes(f.claves.rol)).map(f => [f.pieza, { ref: f.ref, commit: f.claves.commit, sha256: f.claves.sha256 }])),
  };
  fs.writeFileSync(path.join(rel, 'manifest.json'), JSON.stringify(manifest, null, 1) + '\n');
  const todos = Object.assign({}, assets, { 'manifest.json': sha256(path.join(rel, 'manifest.json')) });
  fs.writeFileSync(path.join(rel, 'SHA256SUMS'), Object.entries(todos).sort().map(([f, s]) => `${s}  ${f}`).join('\n') + '\n');
  if (notas) {
    const n = [`FFmpeg ${VERSION} para VEATION (Windows x64 y macOS universal, minimo macOS ${manifest.macos_min}).`, '',
      `- FFmpeg ${lock.get('ffmpeg').ref} sin modificar (tarball oficial, firma verificada), GPLv3; driver NVIDIA minimo ${manifest.nvenc_min_driver} (cabeceras ${manifest.nvenc_cabeceras}).`,
      '- Fuente completo y correspondiente: el asset `*-source.tar.xz` (FFmpeg, cada biblioteca enlazada, la toolchain de Windows, la receta y los parches). Como reconstruir: README-SOURCE.md dentro del paquete.',
      '- Avisos de licencia: `FFMPEG-NOTICES.txt`. Identidad de cada archivo: `SHA256SUMS` y `manifest.json`.',
      '- Se publica como pre-release; pasa a release cuando VEATION la acepta tras su tanda completa (FFMPEG-PROPIO.md, fase 5).', '',
      '| asset | sha256 |', '|---|---|', ...Object.entries(todos).sort().map(([f, s]) => `| ${f} | \`${s}\` |`), ''];
    const extra = arg('--notas-extra'); if (extra && fs.existsSync(extra)) n.push(fs.readFileSync(extra, 'utf8'));
    fs.writeFileSync(notas, n.join('\n') + '\n');
  }
  console.log(`avisos manifiesto: ${Object.keys(todos).length} assets en SHA256SUMS`);
  process.exit(0);
}
morir('fase desconocida (textos, notices, manifiesto)');
