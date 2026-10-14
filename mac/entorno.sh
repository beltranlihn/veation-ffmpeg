# mac/entorno.sh - entorno comun de la compilacion del Mac. Se carga con «.» desde los demas scripts.
#
# Compilacion NATIVA: arm64 en el runner macos-15 y x86_64 en macos-15-intel. Despues
# mac/universal.sh une los dos binarios en uno universal, que es el que se publica.
#
# Reglas que este archivo hace cumplir:
#   - nada de Homebrew: el PATH solo tiene las herramientas fijadas por el lock (mac/herramientas.sh)
#     y las del sistema; PKG_CONFIG_LIBDIR apunta SOLO al prefijo propio (nunca PKG_CONFIG_PATH);
#   - minimo de macOS de piezas.conf (13.0, el de Electron 44) en todo lo que se compila;
#   - rutas fijas en /tmp/vf, para que -buildconf y la traza del enlace sean iguales entre ejecuciones;
#   - Xcode el del lock (16.4), comprobado.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tools/lib.sh"

VF_ARCH="${VF_ARCH:-$(uname -m)}"
case "$VF_ARCH" in
    arm64|x86_64) ;;
    *) vf_die "arquitectura no soportada: $VF_ARCH" ;;
esac
[ "$(uname -m)" = "$VF_ARCH" ] || vf_die "la compilacion es NATIVA: este Mac es $(uname -m) y se pidio $VF_ARCH"
[ "$(uname -s)" = Darwin ] || vf_die "mac/ solo corre en macOS"

VF_SISTEMA="mac-$VF_ARCH"
VF_TMP=/tmp/vf
PREFIX="$VF_TMP/prefix"
VF_HERRAMIENTAS="$VF_TMP/herramientas"
VF_SHIM="$VF_TMP/shim"
VF_TRABAJO="$VF_TMP/trabajo"
VF_DESCARGAS="$VF_TMP/descargas"
VF_FFMPEG_DIR="$VF_TMP/ffmpeg"
MACOS_MIN="$(vf_piezas_valor macos-min)"
NPROC="$(sysctl -n hw.ncpu)"

case "$VF_ARCH" in
    arm64)  VPX_TARGET="arm64-darwin22-gcc" ;;     # darwin22 = macOS 13; desde darwin20 libvpx solo pone -arch
    x86_64) VPX_TARGET="x86_64-darwin22-gcc" ;;
esac

export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
export PATH="$VF_HERRAMIENTAS/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH DYLD_LIBRARY_PATH
export CC=clang CXX=clang++
export CFLAGS="-mmacosx-version-min=$MACOS_MIN -O2"
export CXXFLAGS="-mmacosx-version-min=$MACOS_MIN -O2"
export LDFLAGS="-mmacosx-version-min=$MACOS_MIN"
# GNU libtool se instala como glibtool/glibtoolize: «libtool» en macOS es el archivador de Apple, que
# usa mac/deps/25-x265.sh para unir las tres variantes de x265.
export LIBTOOLIZE=glibtoolize
export LIBTOOL=glibtool
export HOMEBREW_NO_AUTO_UPDATE=1

# Argumentos comunes de CMake.
CMAKE_COMUN="-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN -DCMAKE_OSX_ARCHITECTURES=$VF_ARCH -DCMAKE_FIND_FRAMEWORK=NEVER -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local"

vf_comprobar_xcode() {
    local esperado actual
    esperado="$(vf_lock_campo xcode ref)"
    actual="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
    [ "$actual" = "$esperado" ] || vf_die "Xcode $actual seleccionado; el lock pide $esperado (sudo xcode-select -s $(vf_lock_campo xcode origen))"
}
