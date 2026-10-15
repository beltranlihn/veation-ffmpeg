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
`build` comprueba, nada más publicarla, que GitHub la marcó como inmutable (sus assets ya no pueden
cambiar). La inmutabilidad **no impide borrarla**: lo que garantiza que el fuente siga disponible los años
que pide la GPLv3 §6 es el espejo en el servidor de descarga de VEATION, que es requisito para vender
(§4.1), no un refuerzo.

Aparte, y sin relación con FFmpeg, la release `nsis-plugins-electron-builder-<versión>-source` (workflow
`instalador-fuente`) publica el fuente de los dos plug-ins LGPL del instalador de Windows de VEATION
(StdUtils 1.14 y Nsis7z 19.00, los de electron-builder 26.15.2), que su `THIRD-PARTY-NOTICES.txt`
(sección 13) promete. Esa sección tiene que apuntar a esa release, no a la de FFmpeg.

## Licencia

- **Binarios:** FFmpeg 8.1.3 configurado con `--enable-gpl --enable-version3`: **GNU GPL, versión 3 o
  posterior**. Cada biblioteca enlazada conserva su licencia; todas están en `FFMPEG-NOTICES.txt`.
  Ningún componente *nonfree*.
- **Scripts propios:** MIT (`LICENSE`).
- **`win/`:** fork de [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds), MIT (`win/LICENSE`).

FFmpeg es una marca de Fabrice Bellard, creador del proyecto FFmpeg. Alma Digital Studio no es
propietaria de FFmpeg.

`FFMPEG-NOTICES.txt` cubre **solo** lo que va dentro de estos binarios. No sustituye los avisos de
código propio de VEATION: por ejemplo, la implementación de Snappy en JavaScript de su codificador y
decodificador HAP sigue necesitando su aviso BSD-3-Clause en el `THIRD-PARTY-NOTICES.txt` de VEATION.
De la sección de snappy de ese archivo solo puede pasar aquí la frase sobre el libsnappy enlazado en
FFmpeg (§4.4 decía que la sección entera pasaba a `FFMPEG-NOTICES.txt`).

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
| `patches/` | `MODIFICACIONES.md`: inventario de toda modificación de un fuente de terceros (en `veation.1`, dos líneas heredadas de BtbN para zimg y libvpl, y los parches que crosstool-ng aplica a GCC y mingw-w64 al compilar la toolchain); `reserva/`: el parche de snappy del Mac, que NO se aplica |
| `win/` | fork de BtbN @`63ac3265`, recortado y adaptado (`win/VEATION-CAMBIOS.md`) |
| `mac/` | compilación propia desde fuente, nativa en cada arquitectura |
| `tools/` | descarga y verificación, archivado, puertas, prueba de comportamiento, paridad, avisos, paquete de fuente |
| `notices/` | qué textos de licencia tiene cada pieza y su revisión a mano |
| `.github/workflows/` | `build`, `verificar-fuente` (también lo llama `build` antes de publicar), `electron-ffmpeg-source`, `instalador-fuente`, `congelar`, `comprobar` |

Principios:

1. **Lo que se compila es lo que se publica como fuente.** `tools/fetch.sh` descarga y verifica cada
   pieza (commit exacto, etiqueta sin mover, sha256, firma de FFmpeg) y `tools/archivar.sh` la convierte
   en `fuentes/` con `MANIFIESTO.tsv`. Los dos sistemas compilan **solo** desde ahí, sin red; el paquete de
   fuente es esa misma carpeta más la receta. En Windows, hasta la toolchain sale de ahí: crosstool-ng se
   extrae de su archivo en `fuentes/toolchain-win` (no se clona) y compila GCC, binutils y mingw-w64 con
   los tarballs de esa carpeta, sin red y con las descargas prohibidas. Lo único que baja de la red son
   herramientas usadas sin modificar (fijadas por sha256) y los paquetes de Ubuntu de la imagen base
   (`README-SOURCE.md`, dentro del paquete, lo detalla).
2. **Cada puerta sabe fallar.** Cada comprobación tiene un control que la pone en rojo y que se ejecuta
   en la CI: el FFmpeg de Homebrew contra las puertas del Mac, un exe que importa `mfplat.dll` contra la
   de importaciones, el paquete de fuente sin snappy (Windows, Mac y la comprobación de fuentes) y sin el
   tarball de GCC (crosstool-ng) contra la reconstrucción, un objeto para macOS 14 contra el centinela de
   `minos` del enlazador, y tres controles sin compilar en cada push. Cada control exige el **motivo**
   exacto del fallo, no solo que falle. Las puertas estáticas y la prueba de comportamiento se han probado
   contra el binario de gyan que VEATION lleva hoy: salen en rojo exactamente donde deben.
3. **Nada se publica a medias.** Las imágenes Docker (llevan binarios GPL) no salen del runner; la cache
   es la de Actions. Una release se compila en frío, y el paquete de fuente reconstruye los binarios
   (`verificar-fuente`) **antes** de publicarla.

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
- Las dos rodajas se prueban: `ff-checklist` corre nativo en cada runner; el corpus de Windows se
  decodifica con el universal en `macos-15` **y** en `macos-15-intel` (paridad P6 por arquitectura); y la
  puerta F de la rodaja x86_64 (decodificar igual que el juez) se pasa en `macos-15` con Rosetta, porque
  el FFmpeg de Homebrew que hace de juez no tiene bottle para Intel. El juez es la fórmula versionada
  `ffmpeg@8` (la rama 8.1 del candidato, como el 8.1 de gyan en Windows; `tools/juez-mac.sh` lo exige):
  la fórmula `ffmpeg` ya es 9.0.x y decodifica distinto por razones ajenas a la receta.
- `manifest.json` da el `buildconf_sha256` **por arquitectura**: `scripts/comprobar-ffmpeg.mjs` de
  VEATION tiene que elegir el de `process.arch`.

## Primera ejecución (fase 1 del plan, §6)

El repositorio se escribió sin poder compilar (no hay Docker ni WSL en el equipo donde se escribió). Los
pasos 2 y 3 se hicieron el 2026-10-15: `congelar` (ejecución 38591501114, versionada en `dabb5c5` tras
comprobar cada valor fuera del runner) y `build` sin etiqueta, en verde en la ejecución 38762945191 (lo
que midió, en «Lo que midió la primera ejecución»). Orden:

1. **Configurar el repositorio** en GitHub: público, *immutable releases* activadas (Settings › General),
   «Require actions to be pinned to a full-length commit SHA» si está disponible, sin secretos.
2. **Congelar el lock.** Actions › `congelar` › Run workflow. Calcula los commits, sha256 y el digest que
   faltan (`PENDIENTE`): bajar el artefacto, revisar `congelar.patch` y versionarlo
   (`git apply congelar.patch && tools/comprobar-repo.sh --congelado`). El valor de `sde-win` (URL del
   kit de Intel SDE) lo tiene que poner una persona tras leer sus términos; mientras tanto la puerta I sale
   «NO MEDIDA» y `build` sigue.
3. **Compilar** con Actions › `build` › Run workflow (sin etiqueta: no publica; con `verificar_fuente`,
   que viene marcado, reconstruye además desde el paquete de fuente y pasa sus controles negativos). Lo
   esperable en la primera vuelta es que alguna puerta salga en rojo por algo que no se ha podido medir
   aquí (ver «Sigue sin verificar»); se corrige y se repite. Las DLL que importe de verdad el binario pueden pedir
   ampliar `expected/dll-sistema.txt` (solo con DLL del sistema: el job de Windows lo mide contra el
   System32 real).
4. **Revisar los avisos**: leer los textos de `out/avisos/licencias/` (artefacto `release`) y copiar
   las líneas de `revision.txt` (artefacto `avisos-revision`) a `notices/*/REVISADO`. Ejecutar `build`
   con `scancode: true` y revisar `scancode-propuesta.json` (artefacto `scancode`): cada `PENDIENTE` es una
   licencia del fuente que los textos publicados no recogen; se añade su texto a `notices/<pieza>` o se
   escribe por qué no hace falta aviso. Después, copiarla a `notices/scancode-base.json` sin `_estado`.
5. **Fuentes de terceros que publica este repositorio para VEATION**: Actions › `electron-ffmpeg-source`
   con `publicar` (la `ffmpeg.dll` de Electron) y Actions › `instalador-fuente` con `publicar` (StdUtils y
   Nsis7z del instalador; antes, `congelar` calcula el sha256 del archivo de Nsis7z, y el workflow falla si
   ese archivo no trae el fuente).
6. **Etiqueta**: `git tag v8.1.3-veation.1 && git push origin v8.1.3-veation.1`. `build` compila,
   reconstruye desde el paquete de fuente (`verificar-fuente`, llamado antes de publicar), publica la
   pre-release, comprueba que quedó inmutable y que lo publicado es byte a byte lo verificado. Después,
   `verificar-fuente` vuelve a reconstruir la última release una vez al mes (o a mano).

## Lo que midió la primera ejecución (build 38762945191, 2026-10-15)

Todas las puertas en verde, salvo la I (Intel SDE), que sale NO MEDIDA mientras `sde-win` siga PENDIENTE.

- **Windows.** `-hwaccels` lista `amf`; `-filters` trae `ddagrab` y `gfxcapture`; configure no da ningún
  `WARNING`; crosstool-ng se compila desde su archivo y la toolchain entera sin red (sin el tarball de
  GCC falla con `gcc: download failed`). La traza real del enlazador (`--trace` dos veces: archivos
  abiertos y miembros usados) da L4 en verde: el configure de FFmpeg 8.1.3 añade `-latomic` y GNU ld abre
  `libatomic.a`, pero no enlaza ningún miembro suyo. wine necesita un prefijo propio (`WINEPREFIX`): con
  `HOME=/tmp` se niega a crearlo. `windows-2025` trae Media Foundation (la «edición N» no se ejercita en la
  CI) y Defender, que no marca los binarios.
- **Mac.** meson 1.11.2 con el Python de Xcode 16.4, el shim de `libstdc++.tbd`, `STL_LIBS=-lc++` en
  zimg, el centinela de `minos` y `sandbox-exec` sin red, en las dos arquitecturas; `macos-15` tiene
  Rosetta. El juez es `ffmpeg@8`: la fórmula `ffmpeg` ya es 9.0.x y recorta el relleno final del AAC que
  el 8.1 deja. Entre arquitecturas distintas (la rodaja x86_64 contra el juez arm64, y la paridad P6) se
  decodifica en modo reproducible (`-flags +bitexact -idct simple`): por defecto, la IDCT de NEON y la ICT
  de SSE/FMA no dan los mismos bits, y FFmpeg no lo promete. En macOS, una variable sin llaves seguida de
  un carácter no ASCII rompe bash; `tools/comprobar-repo.sh` lo vigila.
- **Workflows.** `verificar-fuente`, llamado desde `build` con el artefacto `release`, reconstruye en las
  tres arquitecturas e iguala `-version`, `-buildconf`, `-encoders` y `-decoders`; los controles negativos
  salen rojos por su motivo exacto (snappy en las tres extracciones, gcc en crosstool-ng).
- **Tiempos.** Imágenes de Windows (toolchain y bibliotecas) unos 70 min y FFmpeg 7 min; Mac arm64 10
  min y x86_64 entre 35 y 40; `verificar-fuente` / win, en frío, 1 h 40 min; la ejecución entera, unas 3 h 10 min.
- **Binarios.** `ffmpeg.exe` 70,7 MB y `ffprobe.exe` 70,5 MB; `ffmpeg` universal 96,7 MB (arm64 37 MB +
  x86_64 59 MB); paquete de fuente 253 MB. No son reproducibles byte a byte entre ejecuciones (cambia el
  sha256; `-buildconf`, `-encoders` y `-decoders` son los mismos, que es lo que compara `verificar-fuente`).

## Sigue sin verificar

- **Caché `gha`.** No acierta: en las ejecuciones 38715153887, 38728167219 y 38735917913, con las
  mismas fuentes (`MANIFIESTO.tsv` idéntico), el paso de crosstool-ng de `base-win64` se volvió a compilar
  entero, y con él todas las bibliotecas. Hoy cada ejecución compila las imágenes de Windows en frío; la causa está por encontrar.
- **Releases.** El campo `immutable` de la API y la descarga de lo publicado contra `SHA256SUMS` (solo
  con etiqueta).
- **Avisos.** Las rutas de `notices/*/pieza.conf` existen en sus versiones (`avisos.mjs textos`, 0
  problemas; 44 textos esperan su revisión a mano). Falta que ScanCode reconozca en los textos las licencias
  que detecta en el fuente (IJG, ISC...) y el escaneo de libgcc, libstdc++, el CRT y winpthreads (`build`
  con `scancode: true`).
- **Instalador.** Que `Nsis7z_19.00.7z` traiga el fuente (el workflow falla si no) y que la etiqueta 1.14
  de StdUtils sea el fuente de la DLL 1.1.4.0 de electron-builder (los binarios no son reproducibles).

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
