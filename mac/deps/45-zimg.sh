# zimg (zscale y tonemap: proxys correctos de HDR). Lleva la MISMA modificacion que en Windows
# (win/scripts.d/50-zimg.sh): una linea «#include <exception>» al principio de src/zimg/api/zimg.cpp.
# En Windows la pone «sed -i '1i ...'» (GNU); aqui se hace igual sin depender del sed de BSD.
#
# STL_LIBS=-lc++: el configure.ac de zimg (release-3.0.6) pone STL_LIBS=-lstdc++ si no se le da otro,
# sin ningun caso para darwin, y zimg.pc lo copia en «Libs.private: @STL_LIBS@»; FFmpeg lo recibe con
# --pkg-config-flags=--static. Es la variable que el propio zimg.pc.in documenta para otro runtime de C++,
# asi que no toca el fuente. Con esto, el UNICO -lstdc++ que llega a FFmpeg en el Mac es el de snappy
# (configure de 8.1.3), y el plan B de patches/MODIFICACIONES.md vuelve a bastar por si solo.
PIEZA=zimg
construir() {
    { printf '#include <exception>\n'; cat src/zimg/api/zimg.cpp; } > zimg.cpp.tmp
    mv zimg.cpp.tmp src/zimg/api/zimg.cpp
    ./autogen.sh
    ./configure --prefix="$PREFIX" --disable-shared --enable-static --with-pic STL_LIBS=-lc++
    make -j"$NPROC"
    make install
    local pc="$PREFIX/lib/pkgconfig/zimg.pc"
    if ! grep -q -- '-lc++' "$pc" || grep -q -- '-lstdc++' "$pc"; then
        cat "$pc" >&2
        vf_die "zimg.pc no quedo con -lc++ (STL_LIBS no se aplico)"
    fi
}
