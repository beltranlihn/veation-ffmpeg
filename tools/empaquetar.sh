#!/usr/bin/env bash
# tools/empaquetar.sh - los zips de la release (FFMPEG-PROPIO.md, 2.5.5 «Assets»), deterministas: mismos
# archivos en el mismo orden, con la fecha del commit y sin atributos extra (zip -X -D, TZ=UTC).
#
#   tools/empaquetar.sh <dir win> <dir mac-universal> <dir build> <dir release>
#
# Deja en <dir release>:
#   veation-ffmpeg-<v>-win-x64.zip            ffmpeg.exe ffprobe.exe COPYING.GPLv3 FFMPEG-NOTICES.txt SOURCE.txt BUILDINFO-win.txt
#   veation-ffmpeg-<v>-win-x64-debug.zip      ffmpeg_g.exe ffprobe_g.exe (con simbolos)
#   veation-ffmpeg-<v>-mac-universal.zip      ffmpeg ffprobe (arm64 + x86_64) COPYING.GPLv3 FFMPEG-NOTICES.txt SOURCE.txt BUILDINFO-mac-*.txt
#   veation-ffmpeg-<v>-mac-universal-debug.zip ffmpeg_g ffprobe_g y los dSYM de cada arquitectura
#   buildconf-win.txt buildconf-mac-arm64.txt buildconf-mac-x86_64.txt (el -buildconf REAL de cada binario, de <dir build>)
# FFMPEG-NOTICES.txt y SOURCE.txt ya tienen que estar en <dir release> (avisos.mjs notices).
. "$(dirname "$0")/lib.sh"

WIN="$(cd "${1:?dir win}" && pwd)"; MAC="$(cd "${2:?dir mac-universal}" && pwd)"
BUILD="$(cd "${3:?dir build}" && pwd)"; REL="$(cd "${4:?dir release}" && pwd)"
command -v zip >/dev/null || vf_die "falta zip"
for f in FFMPEG-NOTICES.txt SOURCE.txt; do [ -f "$REL/$f" ] || vf_die "falta $REL/$f (avisos.mjs notices)"; done
V="$(vf_version)"
EPOCH="$(git -C "$VF_RAIZ" log -1 --format=%ct HEAD)"
export TZ=UTC

# zipear <zip> <dir de trabajo> <archivos...>: fecha fija, orden fijo, sin uid/gid ni extras
zipear() {
    local zipf="$1" dir="$2"; shift 2
    rm -f "$zipf"
    ( cd "$dir"
      find "$@" -exec touch -h -d "@$EPOCH" {} +
      find "$@" \( -type f -o -type d \) | LC_ALL=C sort | zip -X -D -9 -q "$zipf" -@ )
    vf_log "$(basename "$zipf"): $(unzip -Z1 "$zipf" | tr '\n' ' ')"
}

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkdir -p "$T/win"
cp "$WIN/ffmpeg.exe" "$WIN/ffprobe.exe" "$WIN/COPYING.GPLv3" "$REL/FFMPEG-NOTICES.txt" "$REL/SOURCE.txt" "$BUILD/BUILDINFO-win.txt" "$T/win/"
zipear "$REL/veation-ffmpeg-$V-win-x64.zip" "$T/win" ffmpeg.exe ffprobe.exe COPYING.GPLv3 FFMPEG-NOTICES.txt SOURCE.txt BUILDINFO-win.txt
mkdir -p "$T/wind"
cp "$WIN/ffmpeg_g.exe" "$WIN/ffprobe_g.exe" "$T/wind/"
zipear "$REL/veation-ffmpeg-$V-win-x64-debug.zip" "$T/wind" ffmpeg_g.exe ffprobe_g.exe

mkdir -p "$T/mac"
cp "$MAC/ffmpeg" "$MAC/ffprobe" "$MAC/COPYING.GPLv3" "$REL/FFMPEG-NOTICES.txt" "$REL/SOURCE.txt" "$BUILD/BUILDINFO-mac-arm64.txt" "$BUILD/BUILDINFO-mac-x86_64.txt" "$T/mac/"
chmod 755 "$T/mac/ffmpeg" "$T/mac/ffprobe"
zipear "$REL/veation-ffmpeg-$V-mac-universal.zip" "$T/mac" ffmpeg ffprobe COPYING.GPLv3 FFMPEG-NOTICES.txt SOURCE.txt BUILDINFO-mac-arm64.txt BUILDINFO-mac-x86_64.txt
mkdir -p "$T/macd"
cp -R "$MAC/ffmpeg_g" "$MAC/ffprobe_g" "$MAC"/*.dSYM "$T/macd/"
chmod 755 "$T/macd/ffmpeg_g" "$T/macd/ffprobe_g"
( cd "$T/macd" && zipear "$REL/veation-ffmpeg-$V-mac-universal-debug.zip" "$T/macd" ffmpeg_g ffprobe_g $(ls -d *.dSYM) )

for s in win mac-arm64 mac-x86_64; do cp "$BUILD/buildconf-$s.txt" "$REL/buildconf-$s.txt"; done
vf_log "assets empaquetados en $REL"
