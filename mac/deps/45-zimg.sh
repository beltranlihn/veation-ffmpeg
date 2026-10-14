# zimg (zscale y tonemap: proxys correctos de HDR). Lleva la MISMA modificacion que en Windows
# (win/scripts.d/50-zimg.sh): una linea «#include <exception>» al principio de src/zimg/api/zimg.cpp.
# En Windows la pone «sed -i '1i ...'» (GNU); aqui se hace igual sin depender del sed de BSD.
PIEZA=zimg
construir() {
    { printf '#include <exception>\n'; cat src/zimg/api/zimg.cpp; } > zimg.cpp.tmp
    mv zimg.cpp.tmp src/zimg/api/zimg.cpp
    ./autogen.sh
    ./configure --prefix="$PREFIX" --disable-shared --enable-static --with-pic
    make -j"$NPROC"
    make install
}
