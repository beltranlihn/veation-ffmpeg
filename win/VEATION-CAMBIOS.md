# Cambios de veation-ffmpeg sobre BtbN/FFmpeg-Builds

Esta carpeta es un fork de [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) importado en el
commit `63ac3265b0789ea16c7b1f8351cd2ad195a28722` (2026-10-10) como subárbol (`git subtree`, con
`--squash`). Conserva su licencia MIT (`LICENSE`). El historial del repositorio separa tres pasos:

1. **importación sin cambios** (el árbol de `win/` es idéntico, hash a hash, al de BtbN en ese commit);
2. **recorte** a la lista de piezas (FFMPEG-PROPIO.md §3.1 y §2.4.1);
3. **cambios**, todos marcados en el código con `[veation]` y resumidos aquí.

Para traer cambios futuros de BtbN: `git subtree pull --prefix=win https://github.com/BtbN/FFmpeg-Builds <commit> --squash`,
y revisar el diff contra esta lista.

## Qué se recortó

Todos los scripts de `scripts.d/` que no están en la lista de piezas, incluido **`50-dvd/` entero**
(`40-libdvdread.sh` compilaba con `-Dlibdvdcss=enabled`); los parches de aom y aribb24; las imágenes,
variantes y addins de otros sistemas y versiones (queda `addins/8.1.sh`); los workflows de BtbN (publicaban
imágenes en ghcr) y las utilidades de publicación de releases.

## Qué cambia en lo que queda

| Archivo | Cambio | Motivo |
|---|---|---|
| `scripts.d/*.sh` | bloque `>>> veation` con `SCRIPT_PIEZA`, `SCRIPT_REPO` y `SCRIPT_COMMIT`/`SCRIPT_SHA256` que escribe `tools/aplicar-lock.sh` desde `versions.lock` | una sola fuente de versiones (§2.4.2); BtbN sigue el HEAD de cada biblioteca |
| `util/dl_functions.sh`, `download.sh` | ninguna etapa clona ni descarga: `vf_extraer` saca el árbol de `fuentes/` (verificado contra `MANIFIESTO.tsv`) en un contenedor con `--network=none`; si falta un archivo, falla. El `.tar.xz` de cada etapa es determinista (orden por nombre, 0:0, directorios con fecha 0) | lo que se compila es exactamente lo que va al paquete de fuente (§2.5.6); con bytes distintos en cada ejecución la caché `gha` de BuildKit no acertaría nunca (BtbN lo evita guardando `.cache/downloads` con actions/cache) |
| `util/vars.sh` | registro `vf.local` (nada se publica); las etapas `RUN --network=none` | §2.7; una etapa que quisiera bajar algo fallaría a la vista |
| `makeimage.sh` | caché `gha`/`none`/`local` en vez de ghcr; argumentos fijados (digest de Ubuntu, sha256 de herramientas, commit de crosstool-ng); contexto `vf-toolchain` con los tarballs de la toolchain | §2.4.6-7 |
| `generate.sh` | comprueba que toda opción que pide un script ya esté en `piezas.conf` | la línea de configure sale solo de `piezas.conf` |
| `build.sh` | FFmpeg desde el tarball 8.1.3 verificado (no `git clone`); configure = `piezas.sh args win`; sin `--extra-version=$(date)` ni `--disable-debug`; reenlazado con `-Wl,--trace`; sin red | §2.4.4 |
| `variants/` | `defaults-gpl.sh` sin opciones propias; `win64-gpl.sh` sin `package_variant`; `dl-only.sh` se conserva para `download.sh` | el empaquetado lo hacen `tools/empaquetar.sh` y `tools/fuentes.sh` |
| `images/base/Dockerfile` | `FROM` por digest; autoconf (.deb), CMake 3.31.9 y meson fijados por sha256; sin rustup ni el `curl \| bash` de nodesource | §2.4.6; x265 4.1 no configura con CMake 4 |
| `images/base-win64/Dockerfile`, `ct-ng-config` | crosstool-ng desde su archivo de `fuentes/toolchain-win` (no `git clone`), con `.tarball-version` sacado de `CT_VERSION`; el paso entero con `RUN --network=none`; tarballs de la toolchain desde la misma carpeta con `CT_FORBID_DOWNLOAD=y`; sin destino de Rust | §2.4.6 y §4.2 (la toolchain que se compila es la que se publica, y nada de ella viene de la red) |
| `scripts.d/10-mingw.sh`, `20-libiconv.sh`, `25-xz.sh`, `50-amf.sh`, `50-libmp3lame.sh`, `50-libopus.sh`, `50-svtav1.sh`, `50-x265.sh`, `50-zimg.sh` | sin `ffbuild_dockerdl` propio (usan `default_dl`) | el árbol sale de `fuentes/` |
| `scripts.d/20-libiconv.sh`, `25-xz.sh` | sin `autogen.sh` | tarball de release con `configure` (libiconv 1.19, xz 5.8.4) |
| `scripts.d/50-libmp3lame.sh` | LAME 3.100 (tarball) en vez del trunk de svn r6835 | la versión de gyan, ya validada (§1.5) |
| `scripts.d/50-libopus.sh` | tarball 1.6.1 en vez de git + `autogen.sh` | el tarball ya trae el modelo DNN; `autogen.sh` lo bajaba de la red |
| `scripts.d/50-ffnvcodec.sh` | una sola rama (`n12.1.14.0`, driver ≥ 531.61); sin `--enable-cuda-llvm` | decisión de Beltrán; los filtros CUDA no se usan |
| `scripts.d/50-x264.sh` | `--disable-opencl` | igual que en el Mac; la app no usa OpenCL |
| `scripts.d/50-x265.sh` | `-DENABLE_HDR10_PLUS=OFF` en las tres variantes; sin el `sed` de `json11.cpp` | HDR10+ tiene programa de licencias propio (§2.4.3) |
| `scripts.d/20-bzip2.sh` | **nuevo** | BtbN no tiene bzip2 y `--enable-bzlib` está en la lista (§2.4.1) |
| `scripts.d/15-base.sh`, `zz-final.sh` | dependencias reducidas a las piezas que quedan (+ bzip2) | recorte |

Las órdenes que modifican un árbol de terceros (`sed -i` de zimg y libvpl, líneas añadidas a `.pc`) se
heredan de BtbN sin cambios y están inventariadas en `patches/MODIFICACIONES.md`.
