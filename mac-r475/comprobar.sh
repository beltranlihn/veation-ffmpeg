#!/usr/bin/env bash
# mac-r475/comprobar.sh <ffmpeg> <informe> - lo que VEATION le pide al FFmpeg del Mac (main.js y app.js), medido en el binario:
#   · que no dependa de nada fuera del sistema (otool -L: ni /opt/homebrew ni /usr/local ni el prefijo de la compilación) y su macOS mínimo;
#   · la versión, y que la configuración no lleve nada de DVD ni bibliotecas que no son las de la receta;
#   · que liste los codificadores, decodificadores, filtros y formatos que usa la app;
#   · un encode corto de cada codificador que se pueda en la VM del runner (x264, x265 8 y 10 bits, HAP y HAP Q, aac_at, png, libvpx-vp9
#     y su decodificador). VideoToolbox: se INTENTA; si el runner no lo tiene se dice «NO MEDIDO», no se da por bueno.
# Sale con 1 si falla algo obligatorio.
set -uo pipefail
FF="$1"; INF="$2"; T="$(mktemp -d)"; MAL=0
: > "$INF"
di() { echo "$*" | tee -a "$INF"; }
ok() { if [ "$1" = 0 ]; then di "OK    $2"; else di "MAL   $2"; MAL=1; fi; }

di "== binario: $FF"
di "sha256: $(shasum -a 256 "$FF" | cut -d' ' -f1)  tamaño: $(stat -f %z "$FF") bytes"
V="$("$FF" -hide_banner -version | head -1)"; di "$V"
echo "$V" | grep -q 'ffmpeg version n8.1.3-18-g46d899d7a0-veation-r475 '; ok $? "versión n8.1.3-18-g46d899d7a0 (la misma que Windows)"

di "== otool -L"
otool -L "$FF" | tee -a "$INF" >/dev/null
! otool -L "$FF" | tail -n +2 | grep -Ev '^[[:space:]]+(/usr/lib/|/System/Library/)' | grep -q .; ok $? "otool -L: sólo /usr/lib y /System/Library (nada de /opt/homebrew, /usr/local ni el prefijo)"
MINOS="$(otool -l "$FF" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"; di "minos: $MINOS"
[ "$MINOS" = "12.0" ]; ok $? "macOS mínimo 12.0"
file "$FF" | tee -a "$INF" | grep -q 'arm64'; ok $? "arm64"

di "== configuración"
BC="$("$FF" -hide_banner -buildconf)"; echo "$BC" >> "$INF"
! echo "$BC" | grep -qi 'dvd'; ok $? "sin nada de DVD"
for o in --disable-libxcb --disable-xlib --enable-gpl --enable-version3 --enable-videotoolbox --enable-audiotoolbox --enable-neon --enable-libx264 --enable-libx265 --enable-libvpx --enable-libsnappy --disable-ffplay --disable-sdl2 --disable-doc --disable-debug; do
  echo "$BC" | grep -q -- "$o"; ok $? "configure $o"; done
N_LIBS="$(echo "$BC" | grep -o -- '--enable-lib[a-z0-9]*' | sort -u | tr '\n' ' ')"; di "bibliotecas: $N_LIBS"
[ "$N_LIBS" = "--enable-libsnappy --enable-libvpx --enable-libx264 --enable-libx265 " ]; ok $? "SÓLO x264, x265, libvpx y snappy"

ENC="$("$FF" -hide_banner -encoders)"; DEC="$("$FF" -hide_banner -decoders)"; FIL="$("$FF" -hide_banner -filters)"; FMT="$("$FF" -hide_banner -formats)"
di "== codificadores"; for e in libx264 libx265 h264_videotoolbox hevc_videotoolbox hap aac_at aac png libvpx-vp9 rawvideo; do echo "$ENC" | grep -Eq "^ [A-Z.]{6} $e( |$)"; ok $? "encoder $e"; done
di "== decodificadores"; for d in h264 hevc prores dnxhd vp9 libvpx-vp9 av1 mpeg2video mjpeg png rawvideo hap dxv aac pcm_s16le; do echo "$DEC" | grep -Eq "^ [A-Z.]{6} $d( |$)"; ok $? "decoder $d"; done
di "== filtros"; for f in scale format pad anoisesrc amerge color; do echo "$FIL" | grep -Eq "^ [A-Z.|]{2,3} $f "; ok $? "filtro $f"; done
di "== formatos"; for f in mp4 mov adts null rawvideo lavfi matroska mxf avi image2; do echo "$FMT" | grep -Eq "[ ,]$f[ ,]"; ok $? "formato $f"; done

di "== encodes cortos"
SRC=(-f lavfi -i "testsrc2=s=640x360:r=30:d=1")
"$FF" -v error -y "${SRC[@]}" -c:v libx264 -pix_fmt yuv420p "$T/x264.mp4"; ok $? "libx264 → mp4"
"$FF" -v error -y "${SRC[@]}" -c:v libx265 -pix_fmt yuv420p "$T/x265.mp4"; ok $? "libx265 8 bits → mp4"
"$FF" -v error -y "${SRC[@]}" -c:v libx265 -pix_fmt p010le "$T/x265-10.mp4"; ok $? "libx265 Main 10 (p010le) → mp4"
P10="$("$FF" -hide_banner -i "$T/x265-10.mp4" 2>&1 | grep -o 'yuv420p10le' | head -1)"
[ "$P10" = "yuv420p10le" ]; ok $? "y el resultado es 10 bits (yuv420p10le)"
"$FF" -v error -y "${SRC[@]}" -c:v hap "$T/hap.mov"; ok $? "hap → mov"
"$FF" -v error -y "${SRC[@]}" -c:v hap -format hap_q -compressor snappy "$T/hapq.mov"; ok $? "hap_q con snappy → mov"
"$FF" -v error -i "$T/hapq.mov" -f null -; ok $? "y se decodifica (hap)"
"$FF" -v error -y "${SRC[@]}" -frames:v 1 -c:v png "$T/f.png"; ok $? "png"
"$FF" -v error -y "${SRC[@]}" -c:v libvpx-vp9 -b:v 1M -deadline realtime "$T/v.webm"; ok $? "libvpx-vp9 → webm"
"$FF" -v error -c:v libvpx-vp9 -i "$T/v.webm" -f null -; ok $? "y se decodifica con libvpx-vp9"
"$FF" -v error -y -f lavfi -i 'anoisesrc=r=48000:c=white:seed=1:d=2[a];anoisesrc=r=48000:c=white:seed=2:d=2[b];[a][b]amerge' -c:a aac_at -b:a 320k -f adts "$T/a.aac"; ok $? "aac_at 320k → adts (lo que mide la sonda de la app)"
KB=$(( $(stat -f %z "$T/a.aac") * 8 / 2 / 1000 )); di "aac_at: $KB kbps medidos"

di "== VideoToolbox (si el runner lo tiene)"
for e in h264_videotoolbox hevc_videotoolbox; do
  if "$FF" -v error -y "${SRC[@]}" -c:v "$e" -b:v 2M "$T/$e.mp4" 2> "$T/$e.err"; then di "OK    $e codifica en este runner"
  else di "NO MEDIDO  $e: el runner no lo da ($(head -c 200 "$T/$e.err" | tr '\n' ' ')) — se mide en el Mac de verdad"; fi
done
rm -rf "$T"
[ "$MAL" = 0 ] && di "== TODO LO OBLIGATORIO, VERDE" || di "== HAY FALLOS"
exit "$MAL"
