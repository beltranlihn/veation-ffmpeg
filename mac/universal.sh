#!/usr/bin/env bash
# mac/universal.sh - une los binarios finos arm64 y x86_64 en uno universal (el asset del Mac).
#
#   mac/universal.sh <dir arm64> <dir x86_64> <dir salida>
#
# Por que universal (decision documentada en README.md): VEATION fija UN binario por sistema
# (vendor/ffmpeg/mac + su sha256) y no sabe todavia si publicara un .app universal o dos; el universal
# sirve para los dos casos sin tocar electron-builder (en un .app universal hay que declararlo en
# x64ArchFiles). Cada rodaja conserva su firma ad hoc, y «lipo -thin» la recupera intacta.
#
# Lo que se comprueba aqui, ademas de las puertas de mac/comprobar.sh:
#   - cada rodaja del universal es BYTE A BYTE el binario fino que ya paso todas las puertas en su
#     propio runner (lipo -thin + cmp). Asi no hace falta ejecutar la rodaja x86_64 con Rosetta.

. "$(dirname "$0")/entorno.sh"

ARM="${1:?dir arm64}"; X86="${2:?dir x86_64}"; OUT="${3:?dir salida}"
mkdir -p "$OUT"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for b in ffmpeg ffprobe ffmpeg_g ffprobe_g; do
    [ "$(lipo -archs "$ARM/$b")" = arm64 ] || vf_die "$ARM/$b no es arm64"
    [ "$(lipo -archs "$X86/$b")" = x86_64 ] || vf_die "$X86/$b no es x86_64"
    lipo -create -output "$OUT/$b" "$X86/$b" "$ARM/$b"
    for a in arm64 x86_64; do
        lipo -thin "$a" -output "$tmp/$b-$a" "$OUT/$b"
        orig="$ARM/$b"; [ "$a" = x86_64 ] && orig="$X86/$b"
        cmp -s "$tmp/$b-$a" "$orig" || vf_die "la rodaja $a de $b no es identica al binario fino"
        codesign --verify --strict "$tmp/$b-$a" || vf_die "la rodaja $a de $b no conserva la firma"
    done
done
for a in arm64 x86_64; do
    src="$ARM"; [ "$a" = x86_64 ] && src="$X86"
    rm -rf "$OUT/ffmpeg_g-$a.dSYM" "$OUT/ffprobe_g-$a.dSYM"
    cp -R "$src/ffmpeg_g.dSYM" "$OUT/ffmpeg_g-$a.dSYM"
    cp -R "$src/ffprobe_g.dSYM" "$OUT/ffprobe_g-$a.dSYM"
done
cp "$ARM/COPYING.GPLv3" "$OUT/COPYING.GPLv3"
cmp -s "$ARM/COPYING.GPLv3" "$X86/COPYING.GPLv3" || vf_die "COPYING.GPLv3 distinto entre arquitecturas"

"$(dirname "$0")/comprobar.sh" "$OUT" "x86_64 arm64"
vf_log "universal listo en $OUT"
