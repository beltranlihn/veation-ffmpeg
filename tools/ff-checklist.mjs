/* tools/ff-checklist.mjs - prueba «no se pierde nada» del FFmpeg de VEATION (FFMPEG-PROPIO.md, 5.6).
   COPIA CANONICA. VEATION guarda una copia en scratchpad/ff-checklist.mjs con una cabecera que dice de
   que etiqueta de este repositorio sale. Solo Node, sin dependencias, y sin importar nada del repo:
   tiene que funcionar suelto.

   Uso:  node ff-checklist.mjs <ffmpeg candidato> [opciones]
     --os win|mac              sistema (por defecto, el de esta maquina)
     --juez <ffmpeg>           FFmpeg de banco que NO se distribuye: fabrica el material y decodifica en
                               paralelo para comparar (Windows: el «8.1-full_build» de gyan; Mac: ffmpeg@8 de Homebrew)
     --sin-juez                sin FFmpeg de banco aunque haya uno instalado (F sale SALTADO)
     --probe <ffprobe>         ffprobe para juzgar las salidas (por defecto el del juez, si no el hermano
                               del candidato)
     --version-esperada <v>    p. ej. 8.1.3-veation.1 (si no, se deduce de versions.lock y piezas.conf)
     --nvenc-min <driver>      cadena del driver NVENC minimo que tiene que llevar el binario (531.61)
     --macos-min <version>     minos que tiene que tener el binario del Mac (13.0)
     --solo-cpu                no prueba codificadores de GPU (runners sin GPU)
     --ci                      VideoToolbox con -allow_sw 1; los tiempos (J3) solo se informan
     --mf 0|1                  (Windows) si hay Media Foundation. Con 0 el equipo hace de «edicion N»:
                               aac_mf TIENE que fallar y el export tiene que salir sin AAC
     --solo <lista>            bloques a ejecutar (A,B,C,D1..D5,E,F,G,H,J o alias version,otool,hap)
     --json <archivo>          resultado en JSON
     --corpus-dir <dir>        (F) deja ahi el corpus de video fabricado por el juez
     --corpus-salida <json>    (F) framemd5 del candidato por archivo del corpus, decodificado en modo
                               reproducible (-flags +bitexact -idct simple; tools/corpus.mjs hace lo mismo
                               en el otro sistema con esos archivos: paridad P6)
     --bitexact                (F) juez y candidato decodifican en modo reproducible: para comparar dos
                               ARQUITECTURAS distintas (la rodaja x86_64 del Mac contra el juez arm64)
   Codigos: 0 todo bien · 1 algun FALLO. N-A = hardware ausente en ESTA maquina (se lista, no es fallo).
   SALTADO = perdida deliberada de la v1 (FFMPEG-PROPIO.md, 3.8) o el juez no fabrica ese formato.

   Correcciones de la critica aplicadas: A1 exacta; A3 con dvdcss/dvdread/dvdnav/lcevc/vulkan; filtro
   anullsrc; C con prores/prores_ks_vulkan/aac y vvc_qsv; D2 con AAC del sistema a 320k Y a 192k; G
   con la prohibicion de importar Media Foundation; H (driver NVENC) y J (rutas y caudal) nuevas. */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
import { fileURLToPath } from 'node:url';

const A = process.argv.slice(2);
const FF = A[0]; if (!FF || FF.startsWith('--')) { console.log('uso: node ff-checklist.mjs <ffmpeg> [--os win|mac] [--juez X] [--probe Y] [--solo-cpu] [--ci] [--mf 0|1] [--solo bloques]'); process.exit(2); }
const opt = k => { const i = A.indexOf(k); return i > 0 ? A[i + 1] : null; };
const flag = k => A.includes(k);
const OS = opt('--os') || (process.platform === 'win32' ? 'win' : 'mac');
const SOLO_CPU = flag('--solo-cpu'), CI = flag('--ci'), BITEXACT_F = flag('--bitexact');
const MF = opt('--mf') === null ? true : opt('--mf') === '1';
const ALIAS = { version: 'A1', otool: 'G', hap: 'D3' };
const SOLO = opt('--solo') ? opt('--solo').split(',').map(s => ALIAS[s] || s) : null;
const toca = id => !SOLO || SOLO.some(s => id === s || id.startsWith(s + '.') || (s.length === 1 && id.startsWith(s)));

/* listas de piezas.conf si estamos dentro del repositorio; si no (copia de VEATION), las de aqui */
const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const seccion = (() => { try { const t = fs.readFileSync(path.join(RAIZ, 'piezas.conf'), 'utf8'); return s => { const m = new RegExp('^\\[' + s + '\\]\\s*$([\\s\\S]*?)(?=^\\[|(?![\\s\\S]))', 'm').exec(t); return m ? m[1].split(/\r?\n/).filter(l => l.trim() && !l.trim().startsWith('#')).join(' ').split(/\s+/).filter(Boolean) : null; }; } catch { return () => null; } })();
const lista = (s, defecto) => seccion(s) || defecto.split(' ');
const ENC_PROHIBIDOS = lista('codificadores-prohibidos', 'prores prores_aw prores_ks prores_ks_vulkan aac ac3 ac3_fixed eac3 ac3_mf truehd mlp dca mpeg4 msmpeg4 msmpeg4v2 msmpeg4v3 dxv libx264rgb libvvenc libxeve libxvid libopencore_amrnb libvo_amrwbenc libaom_av1 librav1e libsvtjpegxs liboapv libfdk_aac');
const DEC_PROHIBIDOS = lista('decodificadores-prohibidos', 'vvc vvc_qsv');
const PROTO_PROHIBIDOS = lista('protocolos-prohibidos', 'http https tcp udp rtmp rtp srt tls ftp');
const BC_PROHIBIDO = lista('buildconf-prohibido', 'nonfree libfdk libmpeghdec libnpp cuda-nvcc cuda-sdk cuda-llvm decklink opencore vvenc xeve xevd xvid svtjpegxs oapv frei0r avisynth ladspa rubberband vidstab davs2 xavs2 uavs3d whisper dvdcss dvdread dvdnav lcevc vulkan opencl libplacebo shaderc');
const BC_OBLIGATORIO = lista('buildconf-obligatorio', '--enable-gpl --enable-version3 --disable-autodetect --disable-network --disable-encoders');
const valorGlobal = (k, defecto) => { try { const m = new RegExp('^' + k + '=(.*)$', 'm').exec(fs.readFileSync(path.join(RAIZ, 'piezas.conf'), 'utf8')); return m ? m[1].trim() : defecto; } catch { return defecto; } };
const NVENC_MIN = opt('--nvenc-min') || valorGlobal('nvenc-min-driver', '531.61');
const MACOS_MIN = opt('--macos-min') || valorGlobal('macos-min', '13.0');
const VERSION = opt('--version-esperada') || (() => { try {
  const lock = fs.readFileSync(path.join(RAIZ, 'versions.lock'), 'utf8'); const ref = /^ffmpeg\s+\S+\s+\S+\s+\S+\s+(\S+)/m.exec(lock)[1];
  const extra = /^--extra-version=(\S+)/m.exec(fs.readFileSync(path.join(RAIZ, 'piezas.conf'), 'utf8'))[1]; return `${ref}-${extra}`; } catch { return null; } })();

/* el juez de Windows instalado con winget (Gyan.FFmpeg), en la carpeta del usuario que ejecuta; --juez manda sobre esto */
const GYAN = path.join(os.homedir(), 'AppData', 'Local', 'Microsoft', 'WinGet', 'Packages', 'Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe', 'ffmpeg-8.1-full_build', 'bin') + path.sep;
/* --sin-juez: no buscar ninguno (en el runner Intel del Mac no hay FFmpeg de Homebrew con bottle; su F se pasa aparte) */
const JUEZ = flag('--sin-juez') ? null : (opt('--juez') || [GYAN + 'ffmpeg.exe', '/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg'].find(p => fs.existsSync(p) && path.resolve(p) !== path.resolve(FF)));
const hermano = path.join(path.dirname(FF), 'ffprobe' + (OS === 'win' ? '.exe' : ''));
const PROBE = opt('--probe') || (JUEZ && [path.join(path.dirname(JUEZ), 'ffprobe' + (OS === 'win' ? '.exe' : ''))].find(p => fs.existsSync(p))) || (fs.existsSync(hermano) ? hermano : null);
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'veation-ffcheck-'));
const res = { OK: 0, FALLO: 0, 'N-A': 0, SALTADO: 0, AVISO: 0 }; const filas = [];
const out = (st, id, txt) => { res[st]++; filas.push([st, id, txt]); console.log(st.padEnd(7) + ' ' + id.padEnd(8) + ' ' + txt); };
const run = (bin, args, input, cwd) => { const r = spawnSync(bin, args, { encoding: 'latin1', maxBuffer: 1 << 30, input, timeout: 600000, cwd }); return { code: r.status, out: r.stdout || '', err: (r.stderr || '') + (r.error ? String(r.error) : '') }; };
const ff = (args, input) => run(FF, ['-hide_banner', '-nostdin', '-y', ...args], input);
const fabricante = JUEZ || FF;   /* sin juez, el candidato fabrica lo que pueda */
const jz = (args) => run(fabricante, ['-hide_banner', '-nostdin', '-y', '-loglevel', 'error', ...args]);
const T = n => path.join(TMP, n);
const ultima = s => (s || '').trim().split(/\r?\n/).pop().slice(0, 120);
const SIN_HW = /amfrt|AMF|No capable devices|No NVENC capable|nvcuda|Cannot load|MFX session|Error initializing|unsupported device|Device creation failed|No device available|not supported by the hardware|Could not open encoder|Error while opening encoder|hardware|Driver does not support|minimum required Nvidia driver/i;
const esGPU = e => /nvenc|amf|qsv|videotoolbox|_mf$/.test(e);
console.log(`ff-checklist: ${FF}\n  os=${OS} juez=${JUEZ || '(ninguno)'} probe=${PROBE || '(ninguno)'} version=${VERSION || '?'} mf=${MF ? 1 : 0}${SOLO_CPU ? ' solo-cpu' : ''}${CI ? ' ci' : ''}${SOLO ? ' solo=' + SOLO.join(',') : ''}`);

/* ---------- listas del candidato ---------- */
const listaDe = (flag, re) => { const s = run(FF, ['-hide_banner', flag]).out; const set = new Set(); for (const l of s.split(/\r?\n/)) { const m = re.exec(l); if (m) set.add(m[1]); } return set; };
const ENC = listaDe('-encoders', /^\s[VAS][F.][S.][X.][B.][D.]\s+(\S+)/), DEC = listaDe('-decoders', /^\s[VAS][F.][S.][X.][B.][D.]\s+(\S+)/);
const FIL = listaDe('-filters', /^\s[T.][S.][C.]?\s+(\S+)\s+\S*->\S*/);
/* -muxers / -demuxers: columnas fijas « DEd nombre» (D demuxer, E muxer, d dispositivo, p. ej. lavfi) */
const MUX = new Set([...listaDe('-muxers', /^ [D ]E[d ] +(\S+)/)].flatMap(n => n.split(',')));
const DMX = new Set([...listaDe('-demuxers', /^ D[E ][d ] +(\S+)/)].flatMap(n => n.split(',')));
const HW = new Set(run(FF, ['-hide_banner', '-hwaccels']).out.split(/\r?\n/).slice(1).map(s => s.trim()).filter(Boolean));
const PROTO = (() => { const s = run(FF, ['-hide_banner', '-protocols']).out; const i = s.indexOf('Input:'), o = s.indexOf('Output:'); return new Set(s.slice(i + 6).split(/\r?\n/).map(x => x.trim()).filter(x => x && !/:$/.test(x))); })();
const n_ = s => s.replace(/-/g, '_');
const tiene = (set, n) => [...set].some(x => n_(x) === n_(n));

/* ---------- A · identidad y licencia ---------- */
if (toca('A1')) { const ver = run(FF, ['-version']).out.split(/\r?\n/)[0]; const esp = VERSION ? `ffmpeg version ${VERSION}` : null; out(esp ? (ver.split(/\s+/).slice(0, 3).join(' ') === esp ? 'OK' : 'FALLO') : 'AVISO', 'A1', `-version: «${ver.slice(0, 70)}»` + (esp ? ` (se espera «${esp}»)` : ' (sin version esperada: comparar a mano)')); }
if (toca('A2')) out(/version 3 of the License/.test(run(FF, ['-hide_banner', '-L']).out) ? 'OK' : 'FALLO', 'A2', '-L declara GPL version 3 or later');
const BC = run(FF, ['-hide_banner', '-buildconf']).out;
if (toca('A3')) { const hay = BC_PROHIBIDO.filter(p => BC.includes(p)); out(hay.length ? 'FALLO' : 'OK', 'A3', '-buildconf sin piezas prohibidas' + (hay.length ? ': ' + hay.join(' ') : '')); }
if (toca('A4')) { const falta = BC_OBLIGATORIO.filter(p => !BC.includes(p)); out(falta.length ? 'FALLO' : 'OK', 'A4', '-buildconf con las banderas de la receta' + (falta.length ? '; faltan: ' + falta.join(' ') : '')); }

/* ---------- B · tiene que estar ---------- */
const B = {
  'enc comun': [ENC, 'libx264 libx265 libsvtav1 libvpx-vp9 hap dnxhd png apng tiff exr dpx mjpeg flac libopus libmp3lame pcm_s16le pcm_s24le pcm_s32le pcm_f32le pcm_s16be pcm_s24be rawvideo wrapped_avframe vnull anull'],
  'enc win': [ENC, 'h264_nvenc hevc_nvenc av1_nvenc h264_amf hevc_amf av1_amf h264_qsv hevc_qsv av1_qsv h264_mf hevc_mf aac_mf', 'win'],
  'enc mac': [ENC, 'h264_videotoolbox hevc_videotoolbox prores_videotoolbox aac_at', 'mac'],
  'dec video': [DEC, 'h264 hevc av1 libdav1d vp8 vp9 libvpx-vp9 prores prores_raw dnxhd cfhd hap notchlc dxv mjpeg jpeg2000 png apng tiff exr dpx webp qoi hdr psd sgi targa bmp gif ffv1 utvideo magicyuv huffyuv ffvhuff rawvideo v210 r210 v410 mpeg2video mpeg1video mpeg4 msmpeg4 vc1 wmv3 h263 dvvideo theora apv cavs'],
  'dec audio': [DEC, 'aac aac_fixed mp3float mp3 mp2 flac alac opus vorbis pcm_s16le pcm_s24le pcm_s24be pcm_s32le pcm_f32le pcm_f64le pcm_alaw pcm_mulaw ac3 eac3 truehd mlp dca wavpack ape tta amrnb amrwb adpcm_ima_qt adpcm_ms wmav2 dsd_lsbf'],
  'dec win': [DEC, 'h264_cuvid hevc_cuvid av1_cuvid vp9_cuvid h264_qsv hevc_qsv av1_qsv', 'win'],
  'filtros': [FIL, 'scale pad color format null anull anullsrc aresample buffer buffersink abuffer abuffersink setsar setpts fps crop zscale tonemap psnr ssim geq vflip hflip scroll rotate hstack vstack testsrc testsrc2 nullsrc sine anoisesrc alphaextract premultiply unpremultiply'],
  'muxers': [MUX, 'mov mp4 null wav rawvideo image2 image2pipe apng s16le matroska webm mxf mxf_opatom ogg opus flac mp3 adts ipod'],
  'demuxers': [DMX, 'mov mp4 matroska webm mxf imf rawvideo wav w64 aiff caf image2 image2pipe avi mpegts mpeg flv ogg flac mp3 aac ivf obu h264 hevc yuv4mpegpipe gif apng dash hls concat lavfi'],
  'hwaccel win': [HW, 'cuda d3d11va dxva2 d3d12va qsv amf', 'win'],
  'hwaccel mac': [HW, 'videotoolbox', 'mac'],
  'protocolos': [PROTO, 'file pipe'],
};
let bi = 0; for (const [k, [set, nombres, so]] of Object.entries(B)) { bi++; if (!toca('B' + bi) || (so && so !== OS)) continue; const f = nombres.split(' ').filter(n => !tiene(set, n)); out(f.length ? 'FALLO' : 'OK', 'B' + bi, k + (f.length ? ' — FALTAN: ' + f.join(' ') : ' (' + nombres.split(' ').length + ')')); }

/* ---------- C · NO tiene que estar ---------- */
const C = {
  'C1': ['codificadores ProRes fuera de VideoToolbox', ENC, ENC_PROHIBIDOS.filter(n => n.startsWith('prores'))],
  'C2': ['codificador aac de FFmpeg (se usa el del sistema)', ENC, ['aac']],
  'C3': ['codificadores con titular activo o sin uso', ENC, ENC_PROHIBIDOS.filter(n => !n.startsWith('prores') && n !== 'aac')],
  'C4': ['protocolos de red', PROTO, PROTO_PROHIBIDOS],
  'C5': ['decodificadores VVC (el pool cobra por decodificador software)', DEC, DEC_PROHIBIDOS],
};
for (const [id, [txt, set, nombres]] of Object.entries(C)) { if (!toca(id)) continue; const f = nombres.filter(n => tiene(set, n)); out(f.length ? 'FALLO' : 'OK', id, txt + (f.length ? ' — PRESENTES: ' + f.join(' ') : ' ausentes')); }

/* ---------- D · las ordenes EXACTAS de la app ---------- */
const VT_SW = CI ? ['-allow_sw', '1'] : [];
const conHw = (e, r, id, txt) => out(r.code === 0 ? 'OK' : (esGPU(e) && SIN_HW.test(r.err) ? 'N-A' : 'FALLO'), id, txt + (r.code ? ' — ' + ultima(r.err) : ''));
if (toca('D1')) {
  const lavfiTest = (enc, w, h, diez) => { const a = ['-loglevel', 'error', '-f', 'lavfi', '-i', `color=c=black:s=${w}x${h}:r=30`, '-frames:v', '2', '-c:v', enc]; if (diez && /nvenc/.test(enc)) a.push('-profile:v', 'main10'); if (/videotoolbox/.test(enc)) a.push(...VT_SW); a.push('-pix_fmt', diez ? 'p010le' : 'yuv420p', '-f', 'null', '-'); return ff(a); };
  let pruebas = OS === 'win' ? [['h264_nvenc', 4096, 4096], ['hevc_nvenc', 7680, 1920], ['hevc_nvenc', 4096, 4096, 1], ['h264_amf', 1920, 1080], ['hevc_amf', 1920, 1080], ['h264_qsv', 1920, 1080], ['hevc_qsv', 1920, 1080], ['libx264', 12000, 2000], ['libx265', 12000, 2000], ['libx265', 1920, 1080, 1]]
    : [['h264_videotoolbox', 4096, 4096], ['hevc_videotoolbox', 4096, 4096], ['hevc_videotoolbox', 4096, 4096, 1], ['libx264', 12000, 2000], ['libx265', 12000, 2000], ['libx265', 1920, 1080, 1]];
  if (SOLO_CPU) pruebas = pruebas.filter(([e]) => !esGPU(e) || (OS === 'mac' && CI));
  let di = 0; for (const [e, w, h, d] of pruebas) { di++; if (!tiene(ENC, e)) { out('FALLO', 'D1.' + di, `ffTest ${e} — el codificador no existe`); continue; } conHw(e, lavfiTest(e, w, h, d), 'D1.' + di, `ffTest ${e} ${w}x${h}${d ? ' 10 bits' : ''}`); }
}

const probe = (f, sel) => PROBE ? run(PROBE, ['-v', 'error', '-select_streams', sel, '-show_entries', 'stream=codec_name,profile,pix_fmt,width,height,color_space,color_primaries,color_transfer,color_range,channels,sample_rate,codec_tag_string', '-of', 'default=nw=1', f]).out : '';
const aacSis = OS === 'win' ? 'aac_mf' : 'aac_at';
const HAY_AAC = OS === 'mac' || MF;
if (toca('D2')) {
  /* export por tuberia nv12 + WAV: relleno de lado impar, etiquetas de color, faststart y el AAC del sistema */
  const W = 1921, H = 1080, EW = 1922, N = 30;
  const raw = run(fabricante, ['-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', `testsrc2=s=${W}x${H}:r=30`, '-frames:v', String(N), '-pix_fmt', 'nv12', '-f', 'rawvideo', '-']);
  const rawBuf = Buffer.from(raw.out, 'latin1');
  jz(['-f', 'lavfi', '-i', 'sine=frequency=440:duration=1:sample_rate=48000', '-ac', '2', '-c:a', 'pcm_s16le', T('mix.wav')]);
  const moovAntes = f => { try { const b = fs.readFileSync(f); let o = 0, moov = -1, mdat = -1; while (o + 8 <= b.length) { let s = b.readUInt32BE(o); const t = b.toString('latin1', o + 4, o + 8); if (s === 1) s = Number(b.readBigUInt64BE(o + 8)); if (t === 'moov') moov = o; if (t === 'mdat') mdat = o; if (s < 8) break; o += s; } return moov >= 0 && mdat >= 0 && moov < mdat; } catch { return false; } };
  const expo = (enc, extra, diez, id, kbps) => {
    const o = T('ex-' + enc + (diez ? '-10' : '') + '-' + kbps + '.part.mp4');
    const audio = HAY_AAC ? ['-c:a', aacSis, '-b:a', kbps + 'k', '-ac', '2'] : ['-an'];
    const a = ['-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'nv12', '-s', W + 'x' + H, '-r', '30', '-i', '-', ...(HAY_AAC ? ['-i', T('mix.wav')] : []),
      '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv', '-vf', `pad=${EW}:${H}:0:0:black`, '-c:v', enc, '-g', '30', '-keyint_min', '30', ...extra,
      ...(/videotoolbox/.test(enc) ? VT_SW : []), '-pix_fmt', diez ? 'p010le' : 'yuv420p', ...(diez && /nvenc/.test(enc) ? ['-profile:v', 'main10'] : []), ...audio, '-shortest', '-movflags', '+faststart', o];
    if (!tiene(ENC, enc)) { out('FALLO', id, `export ${enc} — el codificador no existe`); return; }
    const r = ff(a, rawBuf);
    if (r.code !== 0) { out(esGPU(enc) && SIN_HW.test(r.err) ? 'N-A' : 'FALLO', id, `export ${enc} — ${ultima(r.err)}`); return; }
    const v = probe(o, 'v:0'), au = probe(o, 'a:0');
    const okA = HAY_AAC ? (/codec_name=aac/.test(au) && /channels=2/.test(au)) : au.trim() === '';
    const ok = new RegExp('width=' + EW).test(v) && /color_space=bt709/.test(v) && /color_range=tv/.test(v) && (diez ? /pix_fmt=yuv420p10le/.test(v) : /pix_fmt=yuv420p\b/.test(v)) && okA && moovAntes(o);
    out(PROBE ? (ok ? 'OK' : 'FALLO') : 'SALTADO', id, `export ${enc}${diez ? ' 10 bits' : ''} + ${HAY_AAC ? aacSis + ' ' + kbps + 'k' : 'sin audio (edicion N)'}: ancho par, bt709/tv, ${diez ? 'p010' : 'yuv420p'}, moov delante` + (ok ? '' : ' | ' + (v + au).replace(/\r?\n/g, ' ').slice(0, 160)));
  };
  const NV = ['-preset', 'p7', '-tune', 'hq', '-rc', 'vbr', '-b:v', '60M', '-maxrate', '84M', '-bufsize', '120M', '-spatial-aq', '1', '-temporal-aq', '1', '-rc-lookahead', '32', '-bf', '3'];
  const SW = ['-preset', 'veryfast', '-b:v', '20M', '-maxrate', '28M'];
  const VT = ['-b:v', '60M', '-realtime', '0'];
  if (OS === 'win' && !SOLO_CPU) { expo('h264_nvenc', NV, 0, 'D2.1', 320); expo('hevc_nvenc', NV, 1, 'D2.2', 320); expo('h264_amf', SW.slice(2), 0, 'D2.3', 320); expo('h264_qsv', SW, 0, 'D2.4', 320); }
  if (OS === 'mac') { expo('h264_videotoolbox', VT, 0, 'D2.1', 320); expo('hevc_videotoolbox', VT, 1, 'D2.2', 320); }
  expo('libx264', SW, 0, 'D2.5', 320); expo('libx264', SW, 0, 'D2.6', 192); expo('libx265', SW, 1, 'D2.7', 320);
  if (OS === 'win' && !MF) {   /* «edicion N»: el AAC del sistema tiene que FALLAR, y decirlo */
    const r = ff(['-loglevel', 'error', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-t', '0.2', '-c:a', 'aac_mf', '-b:a', '192k', '-f', 'null', '-']);
    out(r.code !== 0 ? 'OK' : 'FALLO', 'D2.9', 'sin Media Foundation, aac_mf FALLA (la app tiene que dejar el audio en WAV aparte)' + (r.code !== 0 ? ' — ' + ultima(r.err) : ' — ¡FUNCIONO! (¿hay MF y --mf 0 esta mal?)'));
  }
}

if (toca('D3')) {
  /* proxy live HAP: la orden de app.js (~5152), tres formatos, con y sin Snappy, y el alfa del .webm por libvpx */
  jz(['-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', T('src.mp4')]);
  jz(['-f', 'lavfi', '-i', 'color=c=black:s=640x360:r=30:d=1', '-vf', "format=rgba,geq=r='255':g='0':b='0':a='if(lt(X,320),128,255)'", '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuva420p', '-b:v', '2M', T('alfa.webm')]);
  const tam = {};
  const hap = (fmt, comp, src, id) => {
    const o = T(`live-${fmt}-${comp}.mov.part`), entrada = fmt === 'hap_alpha' && /\.webm$/.test(src) ? ['-c:v', 'libvpx-vp9'] : [];
    const r = ff(['-loglevel', 'error', ...entrada, '-i', src, '-map', '0:v:0', '-an', '-sn', '-dn', '-vf', 'scale=512:288:flags=lanczos', '-c:v', 'hap', '-format', fmt, '-compressor', comp, '-chunks', '4', '-f', 'mov', o]);
    const tag = { hap: 'Hap1', hap_q: 'HapY', hap_alpha: 'Hap5' }[fmt];
    let ok = r.code === 0 && (!PROBE || new RegExp('codec_tag_string=' + tag).test(probe(o, 'v:0'))); let extra = '';
    if (ok) tam[fmt + comp] = fs.statSync(o).size;
    if (ok && fmt === 'hap_alpha') { const px = run(FF, ['-hide_banner', '-loglevel', 'error', '-i', o, '-frames:v', '1', '-vf', 'crop=8:8:100:100', '-pix_fmt', 'rgba', '-f', 'rawvideo', '-']).out; const a = px.charCodeAt(3); ok = a > 100 && a < 160; extra = ' alfa izq=' + a; }
    out(ok ? 'OK' : 'FALLO', id, `proxy live ${fmt} ${comp} (${tag})${extra}` + (r.code ? ' — ' + ultima(r.err) : ''));
  };
  hap('hap', 'snappy', T('src.mp4'), 'D3.1'); hap('hap_q', 'snappy', T('src.mp4'), 'D3.2'); hap('hap', 'none', T('src.mp4'), 'D3.3'); hap('hap_alpha', 'snappy', T('alfa.webm'), 'D3.4');
  if (tam.hapsnappy && tam.hapnone) out(tam.hapsnappy < tam.hapnone ? 'OK' : 'FALLO', 'D3.5', `con snappy el HAP pesa menos (${tam.hapsnappy} < ${tam.hapnone})`);
}

if (toca('D4')) {
  const nuevo = (id, txt, args, fichero, comprobar) => { const o = T(fichero); const r = ff(['-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=s=1024x512:r=30:d=0.2', ...args, o]); const p = r.code === 0 ? probe(o, '0') : ''; const ok = r.code === 0 && (!comprobar || !PROBE || comprobar.test(p)); out(ok ? 'OK' : (esGPU(args.join(' ')) && SIN_HW.test(r.err) ? 'N-A' : 'FALLO'), id, txt + (ok ? '' : ' — ' + (ultima(r.err) || p.replace(/\r?\n/g, ' ').slice(0, 120)))); };
  nuevo('D4.1', 'DNxHR HQ 8 bits 4:2:2 .mov', ['-c:v', 'dnxhd', '-profile:v', 'dnxhr_hq', '-pix_fmt', 'yuv422p'], 'dnxhr_hq.mov', /profile=DNXHR HQ/i);
  nuevo('D4.2', 'DNxHR HQX 10 bits .mov', ['-c:v', 'dnxhd', '-profile:v', 'dnxhr_hqx', '-pix_fmt', 'yuv422p10le'], 'dnxhr_hqx.mov', /yuv422p10/);
  nuevo('D4.3', 'DNxHR 444 10 bits .mxf (OP1a)', ['-c:v', 'dnxhd', '-profile:v', 'dnxhr_444', '-pix_fmt', 'yuv444p10le'], 'dnxhr_444.mxf', /yuv444p10/);
  nuevo('D4.4', 'AV1 SVT 10 bits .mp4', ['-c:v', 'libsvtav1', '-preset', '10', '-pix_fmt', 'yuv420p10le'], 'av1.mp4', /codec_name=av1/);
  if (OS === 'win' && !SOLO_CPU) nuevo('D4.5', 'AV1 NVENC .mp4', ['-c:v', 'av1_nvenc', '-pix_fmt', 'yuv420p'], 'av1nv.mp4', /codec_name=av1/);
  nuevo('D4.6', 'VP9 con alfa .webm', ['-vf', 'format=yuva420p', '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuva420p', '-b:v', '4M'], 'vp9a.webm', /codec_name=vp9/);
  nuevo('D4.7', 'PNG 16 bits RGBA', ['-frames:v', '1', '-c:v', 'png', '-pix_fmt', 'rgba64be'], 'x16.png', /rgba64be/);
  nuevo('D4.8', 'TIFF 16 bits', ['-frames:v', '1', '-c:v', 'tiff', '-pix_fmt', 'rgb48le'], 'x16.tif', /rgb48le/);
  nuevo('D4.9', 'EXR half ZIP', ['-frames:v', '1', '-c:v', 'exr', '-format', 'half', '-compression', 'zip16', '-pix_fmt', 'gbrpf32le'], 'x.exr', /codec_name=exr/);
  nuevo('D4.10', 'DPX 10 bits', ['-frames:v', '1', '-c:v', 'dpx', '-pix_fmt', 'gbrp10le'], 'x.dpx', /codec_name=dpx/);
  nuevo('D4.11', 'JPEG', ['-frames:v', '1', '-c:v', 'mjpeg', '-pix_fmt', 'yuvj444p'], 'x.jpg', /mjpeg/);
  nuevo('D4.12', 'secuencia PNG por image2', ['-frames:v', '3', '-c:v', 'png', '-f', 'image2'], 'seq_%03d.png', null);
  if (OS === 'mac') { nuevo('D4.13', 'ProRes 4444 por VideoToolbox', ['-vf', 'format=bgra', '-c:v', 'prores_videotoolbox', '-profile:v', '4444', ...VT_SW], 'pr4444.mov', /codec_name=prores/); nuevo('D4.14', 'ProRes 422 HQ por VideoToolbox', ['-c:v', 'prores_videotoolbox', '-profile:v', 'hq', ...VT_SW], 'prhq.mov', /codec_name=prores/); }
  const audio = (id, txt, args, f, re, debeFallar) => { const o = T(f); const r = ff(['-loglevel', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1:sample_rate=48000', '-ac', '2', ...args, o]); if (debeFallar) { out(r.code !== 0 ? 'OK' : 'FALLO', id, txt + ' FALLA, como en una edicion N' + (r.code === 0 ? ' — ¡FUNCIONO!' : '')); return; } const ok = r.code === 0 && (!PROBE || re.test(probe(o, 'a:0'))); out(ok ? 'OK' : 'FALLO', id, txt + (ok ? '' : ' — ' + ultima(r.err))); };
  audio('D4.20', `AAC del sistema (${aacSis}) 320k .m4a`, ['-c:a', aacSis, '-b:a', '320k'], 'a.m4a', /codec_name=aac/, !HAY_AAC);
  audio('D4.21', `AAC del sistema (${aacSis}) 192k .m4a`, ['-c:a', aacSis, '-b:a', '192k'], 'a192.m4a', /codec_name=aac/, !HAY_AAC);
  audio('D4.22', 'FLAC', ['-c:a', 'flac'], 'a.flac', /codec_name=flac/);
  audio('D4.23', 'Opus .webm', ['-c:a', 'libopus', '-b:a', '256k'], 'a.webm', /codec_name=opus/);
  audio('D4.24', 'MP3 LAME', ['-c:a', 'libmp3lame', '-b:a', '320k'], 'a.mp3', /codec_name=mp3/);
  audio('D4.25', 'WAV 24 bits', ['-c:a', 'pcm_s24le'], 'a.wav', /codec_name=pcm_s24le/);
}

if (toca('D5')) {
  /* lo prohibido FALLA de verdad (no basta con que no salga en la lista) */
  const debeFallar = (id, txt, args, re) => { const r = ff(['-loglevel', 'error', ...args]); out(r.code !== 0 && re.test(r.err) ? 'OK' : 'FALLO', id, txt + (r.code === 0 ? ' — ¡FUNCIONO!' : '')); };
  debeFallar('D5.1', 'prores_ks rechazado', ['-f', 'lavfi', '-i', 'testsrc2=s=320x240:d=0.1', '-c:v', 'prores_ks', '-f', 'null', '-'], /Unknown encoder|not found/i);
  /* «-c:a aac» NO tiene por que fallar: si no hay un codificador llamado «aac», ffmpeg busca el codec
     «aac» y toma el que haya (fftools/ffmpeg_opt.c, find_codec: «Matched encoder 'aac_mf' for codec
     'aac'»), es decir, el AAC del sistema. Lo que no puede pasar es que el codificador usado sea el
     propio de FFmpeg: el mapeo de flujos (nivel info) dice cual es, «aac (native)» con el de FFmpeg y
     «aac (aac_mf)» / «aac (aac_at)» con el del sistema. La primera version exigia «Unknown encoder» y
     salia en rojo con el binario bueno (aac_mf existe); contra el de gyan, que lleva el aac propio,
     esta comprobacion sale en rojo. */
  { const r = ff(['-f', 'lavfi', '-i', 'sine=d=0.1', '-c:a', 'aac', '-f', 'null', '-']);
    const usado = (/-> aac \(([\w-]+)\)/.exec(r.err) || [])[1];
    const ok = usado !== 'native' && (r.code !== 0 || !!usado);
    out(ok ? 'OK' : 'FALLO', 'D5.2', '«-c:a aac» no usa el aac propio de FFmpeg' + (usado ? ` — usa ${usado}` : r.code !== 0 ? ' — no hay ningun AAC: ' + ultima(r.err) : ' — no se sabe cual usa')); }
  const r = ff(['-loglevel', 'warning', '-i', 'http://127.0.0.1:9/x.mp4', '-f', 'null', '-']);
  out(r.code !== 0 && /Protocol not found/i.test(r.err) && !/Connection refused|Connection to tcp/i.test(r.err) ? 'OK' : 'FALLO', 'D5.3', 'http: Protocol not found (sin intentar conectar)' + (r.code === 0 ? ' — FUNCIONO' : ' — ' + ultima(r.err)));
}

/* ---------- E · el banco (las redes de VEATION fabrican y juzgan con FFmpeg) ---------- */
if (toca('E')) {
  if (!fs.existsSync(T('src.mp4'))) jz(['-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', T('src.mp4')]);
  const banco = [['-f', 'lavfi', '-i', 'testsrc2=s=512x512:r=30:d=0.2', '-f', 'lavfi', '-i', 'nullsrc=s=256x256:r=30:d=0.2', '-filter_complex', "[0:v]scale=256:256,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)',vflip,scroll=horizontal=0.02:vertical=0.011,rotate=PI*t*1.5:fillcolor=black[a];[1:v]format=gbrp[b];[a]format=gbrp[c];[c][b]hstack", '-c:v', 'libx264', '-crf', '12', '-x264-params', 'log-level=error', T('banco.mp4')],
    ['-i', T('src.mp4'), '-i', T('src.mp4'), '-lavfi', 'psnr', '-f', 'null', '-'],
    ['-f', 'lavfi', '-i', 'testsrc2=s=512x512:r=30:d=0.2', '-c:v', 'libx265', '-preset', 'ultrafast', '-x265-params', 'crf=12:log-level=error', '-tag:v', 'hvc1', T('banco265.mp4')],
    ['-f', 'lavfi', '-i', 'color=c=0xFF6420:s=1920x1080,format=rgba', '-frames:v', '1', '-c:v', 'png', '-f', 'image2', T('banco.png')],
    ['-f', 'lavfi', '-i', 'color=c=0xFF6420:s=1920x1080', '-frames:v', '1', '-f', 'apng', T('banco.apng')],
    /* proxy de HDR (PQ -> BT.709) con zscale + tonemap: la razon de llevar zimg */
    ['-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=0.2', '-vf', 'format=yuv420p10le,setparams=colorspace=bt2020nc:color_primaries=bt2020:color_trc=smpte2084:range=tv,zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p', '-f', 'null', '-']];
  banco.forEach((a, i) => { const r = ff(['-loglevel', 'error', ...a]); out(r.code === 0 ? 'OK' : 'FALLO', 'E' + (i + 1), 'orden del banco: ' + a.filter(x => !x.includes(TMP)).join(' ').slice(0, 100) + (r.code ? ' — ' + ultima(r.err) : '')); });
}

/* ---------- F · decodificar igual que el juez (lo que el usuario TRAE) ---------- */
if (toca('F')) {
  if (!JUEZ) out('SALTADO', 'F', 'sin FFmpeg de banco (--juez) para fabricar el corpus');
  else {
    const V = [['prores422hq', ['-c:v', 'prores_ks', '-profile:v', '3', '-pix_fmt', 'yuv422p10le'], 'mov'], ['prores4444a', ['-vf', 'format=yuva444p10le', '-c:v', 'prores_ks', '-profile:v', '4', '-pix_fmt', 'yuva444p10le'], 'mov'],
      ['dnxhr_hqx', ['-c:v', 'dnxhd', '-profile:v', 'dnxhr_hqx', '-pix_fmt', 'yuv422p10le'], 'mxf'], ['cfhd', ['-c:v', 'cfhd'], 'mov'], ['hevc10', ['-c:v', 'libx265', '-pix_fmt', 'yuv420p10le', '-x265-params', 'log-level=error'], 'mp4'],
      ['h264_422_10', ['-c:v', 'libx264', '-pix_fmt', 'yuv422p10le', '-profile:v', 'high422'], 'mov'], ['av1_10', ['-c:v', 'libsvtav1', '-pix_fmt', 'yuv420p10le'], 'mkv'], ['vp8', ['-c:v', 'libvpx'], 'webm'],
      ['vp9a', ['-vf', 'format=yuva420p', '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuva420p'], 'webm'], ['ffv1', ['-c:v', 'ffv1'], 'mkv'], ['utvideo', ['-c:v', 'utvideo'], 'avi'], ['magicyuv', ['-c:v', 'magicyuv'], 'avi'],
      ['png16', ['-frames:v', '1', '-c:v', 'png', '-pix_fmt', 'rgba64be'], 'png'], ['tiff16', ['-frames:v', '1', '-c:v', 'tiff', '-pix_fmt', 'rgb48le'], 'tif'], ['exr', ['-frames:v', '1', '-c:v', 'exr', '-format', 'half', '-pix_fmt', 'gbrpf32le'], 'exr'],
      ['dpx10', ['-frames:v', '1', '-c:v', 'dpx', '-pix_fmt', 'gbrp10le'], 'dpx'], ['j2k', ['-frames:v', '1', '-c:v', 'jpeg2000'], 'jp2'], ['dxv', ['-c:v', 'dxv'], 'mov'], ['hapq', ['-c:v', 'hap', '-format', 'hap_q'], 'mov'],
      ['mjpeg', ['-c:v', 'mjpeg'], 'avi'], ['mpeg2', ['-c:v', 'mpeg2video'], 'mpg'], ['mpeg4', ['-c:v', 'mpeg4'], 'avi'], ['webp', ['-frames:v', '1', '-c:v', 'libwebp'], 'webp'], ['qoi', ['-frames:v', '1', '-c:v', 'qoi'], 'qoi'],
      ['vvc', ['-c:v', 'libvvenc'], 'mp4'], ['dv', ['-vf', 'scale=720:480', '-c:v', 'dvvideo', '-pix_fmt', 'yuv411p'], 'dv'], ['gif', ['-c:v', 'gif'], 'gif'], ['tga', ['-frames:v', '1', '-c:v', 'targa'], 'tga'],
      ['apv', ['-c:v', 'liboapv'], 'mkv'], ['jxl', ['-frames:v', '1', '-c:v', 'libjxl'], 'jxl'], ['evc', ['-c:v', 'libxeve'], 'mp4'], ['jpegxs', ['-c:v', 'libsvtjpegxs'], 'mkv']];
    const PERDIDA_DELIBERADA = new Set(['evc', 'jpegxs', 'jxl', 'vvc']);   /* FFMPEG-PROPIO.md, 3.8: si no decodifica, SALTADO */
    const AU = [['aac', ['-c:a', 'aac'], 'm4a'], ['mp3', ['-c:a', 'libmp3lame'], 'mp3'], ['flac', ['-c:a', 'flac'], 'flac'], ['alac', ['-c:a', 'alac'], 'm4a'], ['opus', ['-c:a', 'libopus'], 'opus'], ['vorbis', ['-c:a', 'libvorbis'], 'ogg'],
      ['ac3', ['-c:a', 'ac3'], 'ac3'], ['eac3', ['-c:a', 'eac3'], 'eac3'], ['dts', ['-c:a', 'dca', '-strict', '-2'], 'dts'], ['pcm24be', ['-c:a', 'pcm_s24be'], 'aiff'], ['wavpack', ['-c:a', 'wavpack'], 'wv'], ['mp2', ['-c:a', 'mp2'], 'mp2'],
      ['amrnb', ['-ar', '8000', '-ac', '1', '-c:a', 'libopencore_amrnb'], 'amr']];
    /* Modo reproducible: por defecto, cada arquitectura usa su IDCT y su transformada de color en SIMD
       (en arm64 la IDCT de NEON, que no da los mismos bits que la «simple» de C y de x86_64; en x86 la ICT
       en coma flotante de SSE/FMA para JPEG 2000 9/7). Entre arquitecturas distintas eso no es
       reproducible, y FFmpeg no lo promete: sus propias pruebas (FATE) decodifican con «-flags +bitexact
       -idct simple», que fija la IDCT simple y la DWT 9/7 entera. La build 38730882310 lo midio: la rodaja
       x86_64 contra el juez arm64 dio j2k, mjpeg, mpeg4 y dv distintos. En la misma arquitectura la F se
       compara en el modo por defecto, el que usa VEATION. */
    const REPRODUCIBLE = ['-flags', '+bitexact', '-idct', 'simple'];
    const md5 = (bin, f, extra, rep) => { const r = run(bin, ['-hide_banner', '-loglevel', 'error', ...(rep ? REPRODUCIBLE : []), ...extra, '-i', f, '-map', '0', '-f', 'framemd5', '-']); return r.code === 0 ? r.out.split(/\r?\n/).filter(l => l && l[0] !== '#').join('\n') : null; };
    const pcm = (bin, f) => { const r = run(bin, ['-hide_banner', '-loglevel', 'error', '-i', f, '-map', '0:a:0', '-ac', '1', '-ar', '48000', '-f', 's16le', '-']); return r.code === 0 ? Buffer.from(r.out, 'latin1') : null; };
    const corpus = {};
    let fi = 0;
    /* --corpus-dir: el corpus de video se queda ahi para que el Mac decodifique LOS MISMOS archivos (paridad P6) */
    const CORPUS = opt('--corpus-dir'); if (CORPUS) fs.mkdirSync(CORPUS, { recursive: true });
    for (const [n, a, ext] of V) { fi++; const f = CORPUS ? path.join(CORPUS, 'c-' + n + '.' + ext) : T('c-' + n + '.' + ext); const fab = jz(['-f', 'lavfi', '-i', 'testsrc2=s=320x240:r=30:d=0.2', ...a, f]); if (fab.code !== 0) { out('SALTADO', 'F' + fi, n + ' — el juez no lo fabrica'); continue; }
      const ex = n === 'vp9a' ? ['-c:v', 'libvpx-vp9'] : [], a1 = md5(JUEZ, f, ex, BITEXACT_F), a2 = md5(FF, f, ex, BITEXACT_F);
      if (a2 && opt('--corpus-salida')) { const rep = BITEXACT_F ? a2 : md5(FF, f, ex, true); if (rep) corpus[n] = rep; }
      out(a2 && a1 === a2 ? 'OK' : (PERDIDA_DELIBERADA.has(n) && !a2 ? 'SALTADO' : 'FALLO'), 'F' + fi, 'decodifica ' + n + ' igual que el juez' + (a2 ? (a1 === a2 ? '' : ' — fotogramas DISTINTOS') : (PERDIDA_DELIBERADA.has(n) ? ' — no decodifica (perdida deliberada de la v1)' : ' — NO decodifica'))); }
    for (const [n, a, ext] of AU) { fi++; const f = T('c-' + n + '.' + ext); const fab = jz(['-f', 'lavfi', '-i', 'sine=frequency=1000:duration=0.5:sample_rate=48000', ...(a.includes('-ac') ? [] : ['-ac', '2']), ...a, f]); if (fab.code !== 0) { out('SALTADO', 'F' + fi, n + ' — el juez no lo fabrica'); continue; }
      const p1 = pcm(JUEZ, f), p2 = pcm(FF, f); let dmax = -1; if (p1 && p2 && p1.length === p2.length) { dmax = 0; for (let i = 0; i < p1.length; i += 2) dmax = Math.max(dmax, Math.abs(p1.readInt16LE(i) - p2.readInt16LE(i))); }
      /* con longitudes distintas, el detalle dice cuantas muestras tiene cada uno y como se parecen en el
         tramo comun alineado al principio y al final (para saber si sobra relleno delante o detras) */
      const tramo = (a, b, alFinal) => { const n = Math.min(a.length, b.length), oa = alFinal ? a.length - n : 0, ob = alFinal ? b.length - n : 0; let d = 0; for (let i = 0; i < n; i += 2) d = Math.max(d, Math.abs(a.readInt16LE(oa + i) - b.readInt16LE(ob + i))); return d; };
      const detalle = !p2 ? ' — NO decodifica' : !p1 ? ' — el juez no lo decodifica' : dmax >= 0 ? ` (dif. max ${dmax} LSB)` :
        ` — longitud distinta: juez ${p1.length / 2} muestras, candidato ${p2.length / 2}; tramo comun alineado al principio dif. max ${tramo(p1, p2, false)} LSB, al final ${tramo(p1, p2, true)} LSB`;
      out(dmax >= 0 && dmax <= 2 ? 'OK' : 'FALLO', 'F' + fi, 'decodifica audio ' + n + detalle); }
    const fc = opt('--corpus-salida'); if (fc) fs.writeFileSync(fc, JSON.stringify(corpus, null, 1));   /* paridad Windows <-> Mac en la CI */
  }
}

/* ---------- G · enlazado: nada fuera del sistema ---------- */
if (toca('G')) {
  if (OS === 'win') {
    const imp = (() => { try { const b = fs.readFileSync(FF), pe = b.readUInt32LE(0x3c), nsec = b.readUInt16LE(pe + 6), optsz = b.readUInt16LE(pe + 20), opt0 = pe + 24, magic = b.readUInt16LE(opt0), dd = opt0 + (magic === 0x20b ? 112 : 96), sec0 = opt0 + optsz;
      const rva2off = rva => { for (let i = 0; i < nsec; i++) { const s = sec0 + i * 40, va = b.readUInt32LE(s + 12), sz = Math.max(b.readUInt32LE(s + 8), b.readUInt32LE(s + 16)), raw = b.readUInt32LE(s + 20); if (rva >= va && rva < va + sz) return rva - va + raw; } return -1; };
      const nombre = rva => { const o = rva2off(rva); let e = o; while (b[e]) e++; return b.toString('latin1', o, e); }; const set = new Set();
      for (const [idx, step, nameOff] of [[1, 20, 12], [13, 32, 4]]) { const rva = b.readUInt32LE(dd + idx * 8); if (!rva) continue; let o = rva2off(rva); while (o > 0) { const nr = b.readUInt32LE(o + nameOff); if (!nr) break; set.add(nombre(nr)); o += step; } }
      return [...set]; } catch { return null; } })();
    if (!imp) out('FALLO', 'G1', 'no se pudo leer la tabla de importacion');
    else {
      const mf = imp.filter(d => /^(mfplat|mf|mfreadwrite|evr)\.dll$/i.test(d));
      out(mf.length ? 'FALLO' : 'OK', 'G1', 'ninguna importacion estatica de Media Foundation (mfplat, mf, mfreadwrite, evr)' + (mf.length ? ' — IMPORTA ' + mf.join(' ') : ''));
      if (process.platform === 'win32') { const sys = path.join(process.env.SystemRoot || 'C:/Windows', 'System32'); const fuera = imp.filter(d => !/^api-ms-win-|^ext-ms-/i.test(d) && !fs.existsSync(path.join(sys, d)));
        out(fuera.length ? 'FALLO' : 'OK', 'G2', 'DLL importadas, todas del sistema (' + imp.length + '): ' + (fuera.length ? 'FUERA: ' + fuera.join(' ') : imp.join(' ').slice(0, 150))); }
      else out('N-A', 'G2', 'las DLL solo se pueden buscar en System32 desde Windows');
    }
  } else {
    /* solo las lineas sangradas: en un universal hay una cabecera «<ruta> (architecture x):» por arquitectura */
    const r = run('otool', ['-L', FF]); const fuera = r.out.split(/\r?\n/).filter(s => /^\s/.test(s)).map(s => s.trim().split(' ')[0]).filter(s => s && !/^\/usr\/lib\/|^\/System\//.test(s));
    out(r.code === 0 && !fuera.length ? 'OK' : 'FALLO', 'G1', 'otool -L solo /usr/lib y /System' + (fuera.length ? ' — FUERA: ' + fuera.join(' ') : ''));
    const archs = run('lipo', ['-archs', FF]).out.trim().split(/\s+/).filter(Boolean);
    for (const a of archs) { const v = run('vtool', ['-arch', a, '-show-build', FF]).out; const m = [...v.matchAll(/minos\s+(\S+)/g)].map(x => x[1]); out(m.length && m.every(x => x === MACOS_MIN) ? 'OK' : 'FALLO', 'G2', `vtool ${a}: minos ${m.join(',') || '(ninguno)'} (se pide ${MACOS_MIN})`); }
  }
}

/* ---------- H · driver NVIDIA minimo ---------- */
if (toca('H') && OS === 'win') {
  const b = fs.readFileSync(FF).toString('latin1'); const otros = ['531.61', '551.76', '570.0'].filter(v => v !== NVENC_MIN && b.includes('\0' + v + '\0'));
  out(b.includes('\0' + NVENC_MIN + '\0') ? 'OK' : 'FALLO', 'H', `el binario lleva la cadena del driver NVENC minimo ${NVENC_MIN}` + (otros.length ? ' (lleva tambien ' + otros.join(' ') + ')' : ''));
}

/* ---------- J · Windows: rutas no ASCII, rutas largas y caudal por tuberia ---------- */
if (toca('J') && OS === 'win') {
  const prueba = (bin, dir) => { fs.mkdirSync(dir, { recursive: true }); const i = path.join(dir, 'entrada ñ.mp4'), o = path.join(dir, 'salida á.mp4');
    const a = run(bin, ['-hide_banner', '-nostdin', '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=s=320x240:r=30:d=0.2', '-c:v', 'libx264', i]);
    const b = a.code === 0 ? run(bin, ['-hide_banner', '-nostdin', '-y', '-loglevel', 'error', '-i', i, '-c:v', 'libx264', o]) : a; return b.code === 0 && fs.existsSync(o); };
  const c1 = prueba(FF, T('ruta ñandú á')); const j1 = JUEZ ? prueba(JUEZ, T('juez ñandú á')) : null;
  out(c1 ? 'OK' : 'FALLO', 'J1', 'rutas con «ñ» y «á» en entrada y salida' + (j1 === null ? '' : ` (juez: ${j1 ? 'si' : 'no'})`));
  let larga = T('larga'); while (larga.length < 300) larga = path.join(larga, 'carpeta_con_nombre_largo_' + larga.length);
  const c2 = prueba(FF, larga); const j2 = JUEZ ? prueba(JUEZ, larga + '_juez') : null;
  out(j2 === null ? (c2 ? 'OK' : 'AVISO') : (c2 === j2 ? 'OK' : 'FALLO'), 'J2', `ruta de ${larga.length} caracteres: candidato ${c2 ? 'si' : 'no'}` + (j2 === null ? ' (sin juez: el criterio es el mismo resultado que con gyan)' : `, juez ${j2 ? 'si' : 'no'}`));
  const N = 20, W = 4096, H = 4096, frame = Buffer.alloc(W * H * 3 / 2, 128), entrada = Buffer.concat(Array(N).fill(frame));
  const caudal = bin => { const t0 = process.hrtime.bigint(); const r = run(bin, ['-hide_banner', '-nostdin', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'nv12', '-s', `${W}x${H}`, '-r', '30', '-i', '-', '-f', 'null', '-'], entrada); const s = Number(process.hrtime.bigint() - t0) / 1e9; return r.code === 0 ? N / s : 0; };
  const fc = caudal(FF), fj = JUEZ ? caudal(JUEZ) : 0;
  const ok = fc > 0 && (!fj || fc >= 0.95 * fj);
  out(ok ? 'OK' : (CI ? 'AVISO' : 'FALLO'), 'J3', `caudal nv12 4096² por tuberia: ${fc.toFixed(1)} fps` + (fj ? ` (juez ${fj.toFixed(1)} fps; se pide >= 95 %)` : '') + (CI && !ok ? ' — en la CI los tiempos solo se informan' : ''));
}

console.log(`\nRESUMEN  OK ${res.OK} · FALLO ${res.FALLO} · N-A ${res['N-A']} · SALTADO ${res.SALTADO} · AVISO ${res.AVISO}   (temporal: ${TMP})`);
if (opt('--json')) fs.writeFileSync(opt('--json'), JSON.stringify({ binario: FF, os: OS, resumen: res, filas }, null, 1));
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `### ff-checklist ${OS}${SOLO ? ' (' + SOLO.join(',') + ')' : ''}\n\n| estado | id | detalle |\n|---|---|---|\n` + filas.map(([e, i, t]) => `| ${e} | ${i} | ${t.replace(/\|/g, '\\|')} |`).join('\n') + `\n\nOK ${res.OK} · FALLO ${res.FALLO} · N-A ${res['N-A']} · SALTADO ${res.SALTADO} · AVISO ${res.AVISO}\n\n`);
try { fs.rmSync(TMP, { recursive: true, force: true }); } catch {}
process.exit(res.FALLO ? 1 : 0);
