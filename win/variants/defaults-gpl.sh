# [veation] La linea de configure sale ENTERA de piezas.conf (tools/piezas.sh args win), no de aqui ni
# de los scripts: build.sh se la pasa a configure tal cual y la puerta compara -buildconf con
# expected/buildconf-win.txt. Lo que pidan los scripts (ffbuild_configure) solo se usa para comprobar
# en generate.sh que piezas.conf ya lo contiene. Sin --disable-debug: ffmpeg_g.exe conserva simbolos.
FF_CONFIGURE=""
FF_CFLAGS=""
FF_CXXFLAGS=""
FF_LDFLAGS=""
GIT_BRANCH="no-se-usa"
LICENSE_FILE="COPYING.GPLv3"
