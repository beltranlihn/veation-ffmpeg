#!/usr/bin/env bash
# tools/electron-ffmpeg.sh - fuente de la biblioteca ffmpeg.dll / libffmpeg.dylib (LGPL-2.1) que viaja
# dentro de Electron (FFMPEG-PROPIO.md, 2.5.7 y 4.7). No compila nada: localiza la revision exacta y
# guarda una copia PROPIA del fuente (los «+archive» de gitiles no salen identicos byte a byte).
#
#   tools/electron-ffmpeg.sh [<electron> [<chromium>]] <dir salida>
#   (sin version, las de la fila «electron» de versions.lock: v44.7.0 y Chromium 152.0.7977.130)
#
# Pasos y comprobaciones:
#   1. DEPS de Electron en la etiqueta v<electron>: su chromium_version TIENE que ser <chromium>;
#   2. DEPS de Chromium en la etiqueta <chromium> (gitiles, ?format=TEXT): ffmpeg_revision;
#   3. chromium/third_party/ffmpeg en esa revision (comprobada con rev-parse);
#   4. de Electron: patches/ffmpeg/ (link_with_loader_path.patch), patches/config.json,
#      build/args/{all,release,ffmpeg}.gn, LICENSE. La biblioteca que viaja DENTRO de Electron sale de
#      release.gn (is_component_ffmpeg = true) + all.gn (ffmpeg_branding = "Chrome",
#      proprietary_codecs = true); ffmpeg.gn es la variante «Chromium» sin codecs propietarios del zip
#      ffmpeg-*.zip que Electron publica aparte (se guarda solo como referencia);
#   5. un tar determinista con todo + README.txt, su SHA256SUMS y electron-ffmpeg.json.
. "$(dirname "$0")/lib.sh"

if [ $# -ge 3 ]; then E="${1#v}"; C="$2"; SALIDA="$3"
elif [ $# -eq 2 ]; then E="${1#v}"; C=""; SALIDA="$2"
else E=""; C=""; SALIDA="${1:?uso: electron-ffmpeg.sh [<electron> [<chromium>]] <dir salida>}"; fi
[ -n "$E" ] || E="$(vf_lock_campo electron ref)"; E="${E#v}"
[ -n "$C" ] || C="$(vf_lock_campo electron chromium)"
mkdir -p "$SALIDA"; SALIDA="$(cd "$SALIDA" && pwd)"
export GIT_TERMINAL_PROMPT=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. Electron -> Chromium
curl -fsSL --retry 5 "https://raw.githubusercontent.com/electron/electron/v$E/DEPS" -o "$TMP/electron-DEPS"
cv="$(tr -d ' \n' < "$TMP/electron-DEPS" | grep -o "'chromium_version':'[0-9.]*'" | head -1 | cut -d"'" -f4)"
[ "$cv" = "$C" ] || vf_die "Electron v$E usa Chromium «$cv», no $C"
vf_log "Electron v$E -> Chromium $C"

# 2. Chromium -> revision de third_party/ffmpeg
curl -fsSL --retry 5 "https://chromium.googlesource.com/chromium/src/+/refs/tags/$C/DEPS?format=TEXT" | base64 -d > "$TMP/chromium-DEPS"
rev="$(grep -o "'ffmpeg_revision': *'[0-9a-f]\{40\}'" "$TMP/chromium-DEPS" | grep -o '[0-9a-f]\{40\}' | head -1 || true)"
if [ -z "$rev" ]; then   # formato antiguo: la revision escrita en la propia entrada
    rev="$(tr -d ' \n' < "$TMP/chromium-DEPS" | grep -o "/chromium/third_party/ffmpeg.git'+'@'+'[0-9a-f]\{40\}" | grep -o '[0-9a-f]\{40\}$' | head -1 || true)"
fi
[ -n "$rev" ] || vf_die "no se encontro la revision de third_party/ffmpeg en el DEPS de Chromium $C"
vf_log "Chromium $C -> third_party/ffmpeg $rev"

# 3. el fuente de ffmpeg en esa revision
NOMBRE="electron-v$E-ffmpeg-source"
P="$TMP/$NOMBRE"; mkdir -p "$P/electron"
git init -q "$TMP/ff"
git -C "$TMP/ff" fetch -q --depth=1 https://chromium.googlesource.com/chromium/third_party/ffmpeg "$rev"
[ "$(git -C "$TMP/ff" rev-parse FETCH_HEAD)" = "$rev" ] || vf_die "la revision descargada no es $rev"
git -C "$TMP/ff" archive --format=tar --prefix="chromium-third_party-ffmpeg/" "$rev" | tar -xf - -C "$P"

# 4. lo que Electron le aplica
git clone -q --depth=1 --branch "v$E" --filter=blob:none --sparse https://github.com/electron/electron.git "$TMP/el"
git -C "$TMP/el" sparse-checkout set --no-cone /patches/ffmpeg/ /patches/config.json /build/args/ /LICENSE /DEPS
for x in patches/ffmpeg patches/config.json build/args/all.gn build/args/release.gn build/args/ffmpeg.gn LICENSE DEPS; do
    if [ -e "$TMP/el/$x" ]; then mkdir -p "$P/electron/$(dirname "$x")"; cp -R "$TMP/el/$x" "$P/electron/$x"; fi
done
[ -f "$P/electron/patches/ffmpeg/link_with_loader_path.patch" ] || vf_log "AVISO: Electron v$E no trae patches/ffmpeg/link_with_loader_path.patch"
grep -q 'ffmpeg_branding = "Chrome"' "$P/electron/build/args/all.gn" || vf_log "AVISO: build/args/all.gn no fija ffmpeg_branding = \"Chrome\""
grep -q 'is_component_ffmpeg = true' "$P/electron/build/args/release.gn" || vf_die "build/args/release.gn ya no pone is_component_ffmpeg = true: revisar el README del paquete"
grep -q 'import("//electron/build/args/all.gn")' "$P/electron/build/args/release.gn" || vf_die "build/args/release.gn ya no importa all.gn: revisar el README del paquete"
EPOCH="$(git -C "$TMP/el" log -1 --format=%ct)"

cat > "$P/README.txt" <<EOF
Source code of the FFmpeg library used by Electron $E (Chromium $C)
ffmpeg.dll (Windows) and libffmpeg.dylib inside Electron Framework.framework (macOS).

Built by the Electron project from https://chromium.googlesource.com/chromium/third_party/ffmpeg
at revision $rev (chromium-third_party-ffmpeg/), with the patches Electron applies to it
(electron/patches/ffmpeg/, applied as listed in electron/patches/config.json). The library inside
Electron is built with the GN arguments of electron/build/args/release.gn, which imports all.gn
(ffmpeg_branding = "Chrome", proprietary_codecs = true) and sets is_component_ffmpeg = true.
electron/build/args/ffmpeg.gn (ffmpeg_branding = "Chromium", proprietary_codecs = false) is the
variant of the separate ffmpeg zip that Electron publishes, which is not the one distributed with
VEATION; it is included for reference. Not modified by Alma Digital Studio.

License: GNU Lesser General Public License, version 2.1 or later (see the license files in
chromium-third_party-ffmpeg/). The library is loaded dynamically; you may replace it with a
modified, interface-compatible version. On macOS the application must then be re-signed (for
example: codesign --force --deep --sign - /Applications/VEATION.app) for macOS to load it.

How the revision was located: electron/DEPS (chromium_version = $C) and the DEPS file of Chromium
at tag $C (ffmpeg_revision = $rev).
EOF

# 5. tar determinista
( cd "$TMP" && find "$NOMBRE" -print0 | LC_ALL=C sort -z | tar --null --no-recursion -T - --format=gnu \
    --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' -cf - ) \
    | xz -T1 -6 -c > "$SALIDA/$NOMBRE.tar.xz"
SHA="$(vf_sha256 "$SALIDA/$NOMBRE.tar.xz")"
echo "$SHA  $NOMBRE.tar.xz" > "$SALIDA/SHA256SUMS"
cat > "$SALIDA/electron-ffmpeg.json" <<EOF
{
 "electron": "$E",
 "chromium": "$C",
 "ffmpeg_revision": "$rev",
 "asset": "$NOMBRE.tar.xz",
 "sha256": "$SHA",
 "tag": "electron-v$E-ffmpeg-source",
 "url": "https://github.com/${GITHUB_REPOSITORY:-beltranlihn/veation-ffmpeg}/releases/tag/electron-v$E-ffmpeg-source"
}
EOF
cp "$P/README.txt" "$SALIDA/NOTAS.md"
vf_log "listo: $NOMBRE.tar.xz ($SHA)"
