#!/usr/bin/env bash
# tools/instalador-fuente.sh - fuente de los plug-ins LGPL del instalador NSIS de VEATION (StdUtils y
# Nsis7z), que licenses/THIRD-PARTY-NOTICES.txt de VEATION (seccion 13) promete «in the versions used».
# No es parte de FFmpeg: va a su propia release (workflow instalador-fuente), nunca al paquete de FFmpeg.
#
#   tools/instalador-fuente.sh <dir salida>
#
# Toma las filas rol:instalador de versions.lock:
#   git      commit exacto del lock (y la etiqueta tiene que seguir apuntando a el), sin .git;
#   tarball  sha256 del lock; si es un .7z, tiene que traer FUENTE (.c/.cpp/.h): si solo trae binarios,
#            FALLA en vez de publicar algo que no cumple lo prometido.
# Deja nsis-plugins-electron-builder-<v>-source.tar.xz (tar determinista), SHA256SUMS,
# instalador-fuente.json y NOTAS.md (el README del paquete).
. "$(dirname "$0")/lib.sh"

SALIDA="${1:?uso: instalador-fuente.sh <dir salida>}"
mkdir -p "$SALIDA"; SALIDA="$(cd "$SALIDA" && pwd)"
export GIT_TERMINAL_PROMPT=0
EB="$(vf_lock_campo electron-builder ref)"
NSISRES="$(vf_lock_campo electron-builder nsis-resources)"
NOMBRE="nsis-plugins-electron-builder-$EB-source"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/$NOMBRE"; mkdir -p "$P"
EPOCH=0
lista=""

for pieza in $(vf_lock_piezas "" instalador); do
    url="$(vf_lock_campo "$pieza" origen)"; ref="$(vf_lock_campo "$pieza" ref)"
    [ "$url" != PENDIENTE ] || vf_die "«$pieza» sin origen en el lock"
    case "$(vf_lock_campo "$pieza" tipo)" in
        git)
            commit="$(vf_lock_campo "$pieza" commit)"
            case "$commit" in PENDIENTE|"") vf_die "«$pieza» sin commit (congelar primero)" ;; esac
            g="$TMP/git-$pieza"; git init -q "$g"
            git -C "$g" fetch -q --depth=1 "$url" "$commit"
            git -C "$g" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
            [ "$(git -C "$g" rev-parse HEAD)" = "$commit" ] || vf_die "«$pieza»: el commit descargado no es el del lock"
            remoto="$(git ls-remote "$url" "refs/tags/$ref^{}" "refs/tags/$ref" | awk 'NR == 1 || /\^\{\}$/ { c = $1 } END { print c }')"
            [ -z "$remoto" ] || [ "$remoto" = "$commit" ] || vf_die "«$pieza»: la etiqueta $ref apunta ahora a $remoto (¿movida?)"
            e="$(git -C "$g" log -1 --format=%ct HEAD)"; if [ "$e" -gt "$EPOCH" ]; then EPOCH="$e"; fi
            rm -rf "$g/.git"; mv "$g" "$P/$pieza-$ref-${commit:0:12}"
            lista="$lista$pieza $ref: $url @ $commit"$'\n'
            ;;
        tarball)
            sha="$(vf_lock_campo "$pieza" sha256)"
            case "$sha" in PENDIENTE|"") vf_die "«$pieza» sin sha256 (congelar primero)" ;; esac
            a="$P/$(basename "$url")"
            vf_curl -o "$a" "$url"
            [ "$(vf_sha256 "$a")" = "$sha" ] || vf_die "«$pieza»: el sha256 de $(basename "$a") no es el del lock"
            case "$a" in
                *.7z)
                    command -v 7z >/dev/null || vf_die "falta 7z para comprobar $(basename "$a")"
                    n="$(7z l -slt "$a" | awk -F' = ' '$1 == "Path" && $2 ~ /\.(c|cc|cpp|h|hpp)$/ { n++ } END { print n + 0 }')"
                    [ "$n" -gt 0 ] || vf_die "«$pieza»: $(basename "$a") no trae fuente (ningun .c/.cpp/.h): pedirlo al autor antes de publicar"
                    vf_log "«$pieza»: $(basename "$a") trae $n archivo(s) de fuente"
                    ;;
            esac
            lista="$lista$pieza $ref: $url (sha256 $sha)"$'\n'
            ;;
        *) vf_die "«$pieza»: tipo no admitido" ;;
    esac
done
[ -n "$lista" ] || vf_die "no hay filas rol:instalador en versions.lock"

cat > "$P/README.txt" <<EOF
Source code of the LGPL plug-ins of the VEATION Windows installer
================================================================

The VEATION installer is built with electron-builder $EB, which bundles NSIS plug-ins from its
nsis-resources-$NSISRES package (plugins/x86-unicode). Two of them are licensed under the GNU LGPL:

  StdUtils.dll  version 1.1.4.0 (StdUtils 1.14), by LoRd_MuldeR. GNU LGPL 2.1 or later, with the
                author's clarification for NSIS installers.
  nsis7z.dll    version 19.00.0.0 (Nsis7z 19.00), based on 7-Zip by Igor Pavlov. GNU LGPL 2.1; the
                7-Zip / LZMA SDK code it contains is in the public domain.

This package contains their source code, in the versions used, exactly as published by their
authors (not modified by Alma Digital Studio):

$(printf '%s' "$lista" | sed 's/^/  /')

The SHA-256 of each source and of each DLL is listed in versions.lock of
https://github.com/${GITHUB_REPOSITORY:-beltranlihn/veation-ffmpeg} (rows with rol:instalador).
EOF

( cd "$TMP" && find "$NOMBRE" -print0 | LC_ALL=C sort -z | tar --null --no-recursion -T - --format=gnu \
    --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' -cf - ) \
    | xz -T1 -6 -c > "$SALIDA/$NOMBRE.tar.xz"
SHA="$(vf_sha256 "$SALIDA/$NOMBRE.tar.xz")"
echo "$SHA  $NOMBRE.tar.xz" > "$SALIDA/SHA256SUMS"
cat > "$SALIDA/instalador-fuente.json" <<EOF
{
 "electron_builder": "$EB",
 "nsis_resources": "$NSISRES",
 "asset": "$NOMBRE.tar.xz",
 "sha256": "$SHA",
 "tag": "$NOMBRE",
 "url": "https://github.com/${GITHUB_REPOSITORY:-beltranlihn/veation-ffmpeg}/releases/tag/$NOMBRE"
}
EOF
cp "$P/README.txt" "$SALIDA/NOTAS.md"
vf_log "listo: $NOMBRE.tar.xz ($SHA)"
