# x265 4.1: tres variantes (12, 10 y 8 bits) unidas en una libx265.a, como win/scripts.d/50-x265.sh,
# con HDR10+ apagado en las tres. Se unen con el «libtool -static» de Apple (/usr/bin/libtool), no
# con «ar -M» como en Windows.
# x265 escribe en Libs.private de x265.pc las bibliotecas implicitas del compilador, incluida la ruta
# ABSOLUTA de libclang_rt.osx.a dentro de Xcode: se quita del .pc instalado (no del fuente; ver
# patches/MODIFICACIONES.md) porque FFmpeg la copiaria a su linea de enlace.
PIEZA=x265
construir() {
    local comun="$CMAKE_COMUN -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DCMAKE_ASM_NASM_FLAGS=-w-macro-params-legacy -DENABLE_ALPHA=ON -DENABLE_HDR10_PLUS=OFF"
    cmake $comun -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DMAIN12=ON -S source -B 12bit
    cmake $comun -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -S source -B 10bit
    cmake --build 12bit -j "$NPROC"
    cmake --build 10bit -j "$NPROC"
    mkdir -p 8bit
    cp 12bit/libx265.a 8bit/libx265_main12.a
    cp 10bit/libx265.a 8bit/libx265_main10.a
    cmake $comun -DEXTRA_LIB="x265_main10.a;x265_main12.a" -DEXTRA_LINK_FLAGS=-L. -DLINKED_10BIT=ON -DLINKED_12BIT=ON -S source -B 8bit
    cmake --build 8bit -j "$NPROC"
    (
        cd 8bit
        mv libx265.a libx265_main.a
        /usr/bin/libtool -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a
    )
    cmake --install 8bit
    local pc="$PREFIX/lib/pkgconfig/x265.pc"
    sed -E -e 's#[^ ]*libclang_rt[^ ]*\.a##g' -e 's#  +# #g' "$pc" > "$pc.tmp" && mv "$pc.tmp" "$pc"
    if grep -q -e '/Applications/' -e 'libclang_rt' "$pc"; then
        cat "$pc" >&2
        vf_die "x265.pc sigue con rutas absolutas"
    fi
}
