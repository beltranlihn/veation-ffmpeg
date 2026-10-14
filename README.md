# veation-ffmpeg

Receta pública con la que Alma Digital Studio compila el **FFmpeg que acompaña a VEATION**, el editor de
vídeo inmersivo (domo, 2D y sala 360). Este repositorio contiene solo la receta; los binarios, el
**fuente completo y correspondiente** y los avisos de licencia se publican en sus
[releases](https://github.com/beltranlihn/veation-ffmpeg/releases).

Documento de diseño (en el repositorio de VEATION): `docs/FFMPEG-PROPIO.md`. Las secciones citadas
como «§n» son de ese documento.

## Qué se publica

Cada release `v<FFmpeg>-veation.<N>` (la primera, `v8.1.3-veation.1`) lleva:

| Asset | Contenido |
|---|---|
| `veation-ffmpeg-<v>-win-x64.zip` | `ffmpeg.exe`, `ffprobe.exe`, `COPYING.GPLv3`, `FFMPEG-NOTICES.txt`, `SOURCE.txt`, `BUILDINFO-win.txt` |
| `veation-ffmpeg-<v>-mac-universal.zip` | `ffmpeg` y `ffprobe` universales (arm64 + x86_64, macOS 13.0 o posterior), los mismos avisos, `BUILDINFO-mac-*.txt` |
| `…-win-x64-debug.zip`, `…-mac-universal-debug.zip` | los mismos programas con símbolos (`ffmpeg_g`) y los dSYM del Mac |
| `veation-ffmpeg-<v>-source.tar.xz` | el fuente completo: receta, FFmpeg con su firma, cada biblioteca enlazada, la toolchain de Windows, BUILDINFO, traza del enlace y licencias (en partes `.partNN` si pasa de 2 GiB) |
| `FFMPEG-NOTICES.txt` | build, sha256 de cada binario y del fuente, una ficha por componente y los textos de licencia literales |
| `manifest.json`, `SHA256SUMS` | la identidad de todo lo anterior; VEATION fija sus binarios por estos sha256 |
| `buildconf-win.txt`, `buildconf-mac-arm64.txt`, `buildconf-mac-x86_64.txt` | el `-buildconf` real de cada binario |

Se publica como **pre-release** y pasa a release cuando VEATION la acepta tras su tanda completa de
pruebas (§6, fase 5). Una release no se edita ni se borra: un error se corrige con `veation.<N+1>`.

## Licencia

- **Binarios:** FFmpeg 8.1.3 configurado con `--enable-gpl --enable-version3`: **GNU GPL, versión 3 o
  posterior**. Cada biblioteca enlazada conserva su licencia; todas están en `FFMPEG-NOTICES.txt`.
  Ningún componente *nonfree*.
- **Scripts propios:** MIT (`LICENSE`).
- **`win/`:** fork de [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds), MIT (`win/LICENSE`).

FFmpeg es una marca de Fabrice Bellard, creador del proyecto FFmpeg. Alma Digital Studio no es
propietaria de FFmpeg.

## Qué lleva el binario

La lista de piezas es **única** y está en `piezas.conf` (§3): x264, x265 (8, 10 y 12 bits, sin HDR10+),
libvpx, dav1d, SVT-AV1, snappy (HAP), zimg, libxml2, opus, LAME y xz en los dos sistemas; zlib, bzip2,
libiconv, nv-codec-headers `n12.1.14.0` (driver NVIDIA ≥ 531.61), AMF, libvpl y Media Foundation en
Windows; VideoToolbox y AudioToolbox en el Mac.

Fuera, a propósito: todo lo *nonfree*, libdvdcss/libdvdread/libdvdnav, los codificadores ProRes propios
de FFmpeg (ProRes solo por VideoToolbox), el codificador `aac` de FFmpeg (se usa el AAC del sistema;
si el equipo no tiene ninguno, VEATION deja el audio en un WAV aparte), Dolby/DTS y otros con titular
activo, el decodificador VVC, la red (`--disable-network`), Vulkan, OpenCL y los filtros que cargan
código ajeno. Los codificadores van por **lista blanca** (`--disable-encoders` y uno a uno).

## Cómo está hecho

| Carpeta / archivo | Qué es |
|---|---|
| `versions.lock` | **única** fuente de versiones: FFmpeg, bibliotecas, toolchain, herramientas, con su commit o sha256 |
| `piezas.conf` | **única** lista de piezas y línea de configure de cada sistema; lo prohibido que miden las puertas |
| `expected/` | `-buildconf` esperado de cada sistema (generado de `piezas.conf`), lo que puede diferir entre Windows y Mac, DLL de sistema admitidas, avisos de configure admitidos |
| `patches/` | `MODIFICACIONES.md`: inventario de toda modificación de un fuente de terceros (en `veation.1`, dos líneas heredadas de BtbN para zimg y libvpl); `reserva/`: el parche de snappy del Mac, que NO se aplica |
| `win/` | fork de BtbN @`63ac3265`, recortado y adaptado (`win/VEATION-CAMBIOS.md`) |
| `mac/` | compilación propia desde fuente, nativa en cada arquitectura |
| `tools/` | descarga y verificación, archivado, puertas, prueba de comportamiento, paridad, avisos, paquete de fuente |
| `notices/` | qué textos de licencia tiene cada pieza y su revisión a mano |
| `.github/workflows/` | `build`, `verificar-fuente`, `electron-ffmpeg-source`, `congelar`, `comprobar` |

Principios:

1. **Lo que se compila es lo que se publica como fuente.** `tools/fetch.sh` descarga y verifica cada
   pieza (commit exacto, etiqueta sin mover, sha256, firma de FFmpeg) y `tools/archivar.sh` la convierte
   en `fuentes/` con `MANIFIESTO.tsv`. Los dos sistemas compilan **solo** desde ahí, sin red; el paquete de
   fuente es esa misma carpeta más la receta. En Windows, hasta la toolchain (crosstool-ng) se compila
   con los tarballs de `fuentes/toolchain-win` y con las descargas prohibidas.
2. **Cada puerta sabe fallar.** Cada comprobación tiene un control que la pone en rojo y que se ejecuta
   en la CI: el FFmpeg de Homebrew contra las puertas del Mac, un exe que importa `mfplat.dll` contra la
   de importaciones, el paquete de fuente sin snappy contra la reconstrucción, y tres controles sin
   compilar en cada push. Las puertas estáticas y la prueba de comportamiento se han probado contra el
   binario de gyan que VEATION lleva hoy: salen en rojo exactamente donde deben.
3. **Nada se publica a medias.** Las imágenes Docker (llevan binarios GPL) no salen del runner; la cache
   es la de Actions. Una release se compila en frío.

### Decisión: binario universal en el Mac

El Mac se compila **de forma nativa en cada arquitectura** (arm64 en `macos-15`, x86_64 en
`macos-15-intel`, mínimo macOS 13.0 por Electron 44) y se publica **un binario universal** que une los dos:

- VEATION fija **un** binario por sistema (`vendor/ffmpeg/mac/ffmpeg` y su sha256) y su
  `extraResources` no cambia; el universal sirve igual para un `.app` arm64, uno x64 o uno universal
  (en este último, electron-builder necesita la ruta en `x64ArchFiles`).
- Cada rodaja es **byte a byte** el binario fino que pasó todas las puertas en su propio runner
  (`mac/universal.sh` lo comprueba con `lipo -thin` + `cmp`) y conserva su firma ad hoc; `lipo -thin`
  permite recuperar el fino sin invalidar nada si algún día el tamaño importa.
- Compilar x86_64 en su runner evita la compilación cruzada (cada biblioteca con su propia forma de
  hacerla) y permite probarlo sin Rosetta. Coste: unos 2× de tamaño. Límite conocido: GitHub anuncia
  `macos-15-intel` hasta agosto de 2027; después habrá que compilar x86_64 de forma cruzada en arm64.
- `manifest.json` da el `buildconf_sha256` **por arquitectura**: `scripts/comprobar-ffmpeg.mjs` de
  VEATION tiene que elegir el de `process.arch`.

## Primera ejecución (fase 1 del plan, §6)

Nada de esto se ha ejecutado todavía: el repositorio se escribió sin poder compilar (no hay Docker ni
WSL en el equipo donde se escribió). Orden:

1. **Configurar el repositorio** en GitHub: público, *immutable releases* activadas (Settings › General),
   «Require actions to be pinned to a full-length commit SHA» si está disponible, sin secretos.
2. **Congelar el lock.** Actions › `congelar` › Run workflow. Calcula los commits, sha256 y el digest que
   faltan (`PENDIENTE`): bajar el artefacto, revisar `congelar.patch` y versionarlo
   (`git apply congelar.patch && tools/comprobar-repo.sh --congelado`). El valor de `sde-win` (URL del
   kit de Intel SDE) lo tiene que poner una persona tras leer sus términos; mientras tanto la puerta I sale
   «NO MEDIDA» y `build` sigue.
3. **Compilar** con Actions › `build` › Run workflow (sin etiqueta: no publica). Lo esperable en la primera
   vuelta es que alguna puerta salga en rojo por algo que no se ha podido medir aquí (ver «SIN VERIFICAR»);
   se corrige y se repite. Las DLL que importe de verdad el binario pueden pedir ampliar
   `expected/dll-sistema.txt` (solo con DLL del sistema: el job de Windows lo mide contra el System32 real).
4. **Revisar los avisos**: leer los textos de `out/avisos/licencias/` (artefacto `release`) y copiar
   las líneas de `revision.txt` (artefacto `avisos-revision`) a `notices/*/REVISADO`. Ejecutar `build`
   con `scancode: true`, revisar `scancode-resumen.json` y copiarlo a `notices/scancode-base.json`.
5. **Fuente de Electron**: Actions › `electron-ffmpeg-source` con `publicar`.
6. **Etiqueta**: `git tag v8.1.3-veation.1 && git push origin v8.1.3-veation.1`. `build` publica la
   pre-release y `verificar-fuente` la reconstruye desde su paquete de fuente.

## Reconstruir desde el paquete de fuente

Dentro del paquete, `README-SOURCE.md` da los pasos. En resumen: la carpeta raíz del paquete sirve como
`VF_FUENTES`; en el Mac `mac/herramientas.sh` y `mac/construir.sh`; en Linux con Docker
`win/makeimage.sh win64 gpl 8.1` y `win/build.sh win64 gpl 8.1`.

## Comprobaciones locales

    tools/comprobar-repo.sh            # sintaxis, acciones fijadas, lock, piezas, modificaciones
    tools/piezas.sh args win           # la línea de configure de Windows
    tools/piezas.sh buildconf mac-arm64
    node tools/puertas.mjs --sistema win --info <volcado de tools/info-binario.sh> --binario ffmpeg.exe
    node tools/ff-checklist.mjs <ffmpeg> --juez <ffmpeg de banco>
