# Modificaciones a fuentes de terceros

Inventario de **toda** modificación que la receta hace sobre el fuente de una pieza de terceros, sea un
parche de esta carpeta o una orden dentro de un script (FFMPEG-PROPIO.md, 3.7). Sirve a la vez:

- de aviso de «archivos modificados» que piden la GPLv3 §5(a) y la LGPL-2.1 §2(a), con su fecha;
- de lista cerrada: `tools/modificaciones.sh` (lo ejecuta la comprobación de cada push) busca en
  `win/scripts.d/` y `mac/` toda orden que modifique un árbol (`sed -i`, `patch`, `perl -pi`, una línea
  añadida a un archivo del fuente o a un `.pc` instalado) y **falla si no está copiada, letra por letra,
  en un bloque de código de este documento**. También falla si un bloque de aquí ya no aparece en
  ningún script (inventario desfasado).

Fecha de todas las filas: 2026-10-14 (primera versión de la receta, `veation.1`).

## Parches de esta carpeta

Ninguno se aplica en `veation.1`. Cada parche que se añada lleva en su primera línea
`Modified by Alma Digital Studio, AAAA-MM-DD: <qué y por qué>` y el script que lo aplica comprueba que esa
marca quedó en el archivo modificado.

### Reserva: `reserva/ffmpeg-0001-snappy-libcxx.patch` (NO se aplica)

El `configure` de FFmpeg 8.1.3 enlaza snappy con `-lsnappy -lstdc++` (línea 7381), y macOS no tiene
libstdc++. La receta lo resuelve **sin tocar FFmpeg**: `mac/ffmpeg.sh` crea `/tmp/vf/shim/libstdc++.tbd`
apuntando al `libc++.tbd` del SDK y lo pasa con `-L/tmp/vf/shim`. Que el shim funcione está **SIN
VERIFICAR** hasta la primera compilación del Mac. Si no funcionara, el plan B es este parche
(`-lstdc++` → `-lc++`, solo en el Mac); entonces habría que moverlo a `patches/ffmpeg/`, aplicarlo con
comprobación de su marca, añadir aquí su bloque y cambiar la línea «Build» de los avisos a «modified by
Alma Digital Studio on <fecha>» (FFMPEG-PROPIO.md, 4.4).

## Órdenes dentro de los scripts

### zimg (Windows y Mac): `#include <exception>` al principio de `src/zimg/api/zimg.cpp`

`zimg.cpp` usa `std::exception` sin incluir `<exception>`; con GCC 16 no compila. La línea viene de
BtbN y se aplica igual en los dos sistemas, para que los dos compilen el mismo fuente.

Windows (`win/scripts.d/50-zimg.sh`):

```
sed -i '1i #include <exception>' src/zimg/api/zimg.cpp
```

Mac (`mac/deps/45-zimg.sh`; la misma línea sin depender del `sed` de BSD):

```
{ printf '#include <exception>\n'; cat src/zimg/api/zimg.cpp; } > zimg.cpp.tmp
```

### libvpl (Windows): condición de `_MSC_VER` en `libvpl/src/windows/mfx_dispatcher_defs.h`

`#if _MSC_VER < 1400` se evalúa también con mingw (donde `_MSC_VER` no existe y vale 0) y activa código
para Visual C++ antiguo. Viene de BtbN (`win/scripts.d/50-onevpl.sh`):

```
sed -i 's/^#if _MSC_VER < 1400$/#if defined(_MSC_VER) \&\& _MSC_VER < 1400/' libvpl/src/windows/mfx_dispatcher_defs.h
```

## Ajustes de archivos generados (no son fuente de terceros)

No modifican el fuente: cambian el `.pc` que la biblioteca **instala** al compilar, para que FFmpeg
reciba la línea de enlace correcta. Se listan para que nada que toque un árbol quede sin inventariar.

### libvpl y x265 (Windows): `-lstdc++` en `Libs.private` de su `.pc`

Las dos son C++ y su `.pc` no lo declara; sin esto, el enlace estático de FFmpeg falla. De BtbN:

```
echo "Libs.private: -lstdc++" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/vpl.pc
```

```
echo "Libs.private: -lstdc++" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/x265.pc
```

### x265 (Mac): se quita la ruta absoluta de `libclang_rt.osx.a` de `x265.pc`

x265 copia a `Libs.private` las bibliotecas implícitas del compilador, incluida la ruta absoluta de
`libclang_rt.osx.a` dentro de Xcode; FFmpeg la pasaría al enlazador. `mac/deps/25-x265.sh`:

```
sed -E -e 's#[^ ]*libclang_rt[^ ]*\.a##g' -e 's#  +# #g' "$pc" > "$pc.tmp" && mv "$pc.tmp" "$pc"
```

## Lo que NO es una modificación, aunque lo parezca

- **AMF**: el archivo del paquete de fuente lleva solo `amf/public/include` y `LICENSE.txt` (`solo:` en
  `versions.lock`). Son las únicas partes que se compilan (cabeceras MIT); el resto del repositorio (unos
  1,3 GB con binarios de terceros para los ejemplos) no interviene. Los archivos van sin cambios.
- **x265 4.1** dice ser `4.0+1-6318f22`: su `x265Version.txt` de la etiqueta `4.1` no se actualizó en
  origen. Se deja tal cual; cambiarlo sería modificar el fuente para que diga otra cosa.
- **x264** dice ser `0.165.x`: su `version.sh` cuenta commits con git y el paquete de fuente no lleva
  `.git`. El commit exacto está en `versions.lock` y en `MANIFIESTO.tsv`.
- **`win/util/run_stage.sh`** pasa `strip --strip-unneeded --strip-debug` a las `.a` instaladas: procesa
  el resultado de la compilación, no el fuente.
