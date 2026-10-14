# notices/: avisos de licencia revisados a mano

Una carpeta por cada pieza cuyo código acaba dentro de `ffmpeg.exe` / `ffmpeg` (las de `rol:fuente`
del lock, más el runtime del toolchain de Windows: `mingw-w64` y `gcc`).

- `pieza.conf`: nombre visible, licencia (texto y SPDX), `textos=` (las rutas **dentro del fuente** de
  los archivos de licencia, NOTICE y PATENTS) y, si hace falta, `nota=` (una línea más en la ficha de
  `FFMPEG-NOTICES.txt`; `{ref:<pieza>}` se sustituye por la versión del lock). Modos de una ruta:
  - `ruta` — el archivo entero;
  - `ruta#cabecera` — el primer comentario del archivo: `/* … */` o, en ensamblador, el bloque inicial
    de líneas que empiezan por `;` (los `x86inc.asm` de FFmpeg, x264, x265 y dav1d);
  - `ruta#licencia` — el primer comentario que contiene «Permission» o «Redistribution», para archivos
    cuyo primer comentario no es la licencia (`timsort.h` de libxml2).
- `REVISADO`: el sha256 de cada texto **después de leerlo**. Empieza en `PENDIENTE`.

`tools/avisos.mjs textos` extrae esos textos del fuente EXACTO de la versión del lock (los mismos
archivos que van al paquete de fuente), así que lo que se publica en `FFMPEG-NOTICES.txt` es literal.
Cada vez que se ejecuta deja en `out/avisos/revision.txt` los sha256 de hoy:

1. la primera vez (o tras subir una versión), leer cada texto en `out/avisos/licencias/<pieza>/`;
2. si el texto está bien recogido y no trae obligaciones nuevas, copiar su línea a `REVISADO`;
3. si una versión nueva cambia un texto ya revisado, la release se para (`--estricto`) hasta revisarlo.

Además de los archivos de licencia de cada proyecto, van los avisos de archivos sueltos que se compilan
dentro del binario con otra licencia: el código de libjpeg en FFmpeg (licencia del Independent JPEG
Group, que además pide la frase «This software is based in part on the work of the Independent JPEG
Group», puesta en la cabecera de `FFMPEG-NOTICES.txt`), los `x86inc.asm` (ISC), fastfeat en SVT-AV1
(BSD-3-Clause), `dict.c`, `list.c` y `timsort.h` en libxml2, y las cinco cabeceras de nv-codec-headers
(cada una dice que su aviso «applies to this header file only»).

`scancode-base.json` es la base revisada de ScanCode (`tools/scancode.sh`, que escanea también libgcc,
libstdc++, el CRT de mingw-w64 y winpthreads): para cada pieza, cada expresión de licencia que aparece en
su fuente y **cómo se cumple**: `"textos"` (todas sus licencias están en los textos publicados de esa
pieza, y la herramienta lo comprueba escaneando también esos textos) o una justificación escrita de por
qué no hace falta aviso. Una expresión nueva, una sin justificación o una `"textos"` que los textos no
recogen paran la release.

`tools/avisos.mjs notices --enlazado` cruza además la traza real del enlazador (`linked-*.txt` de
`tools/enlazado.mjs`) con estas fichas: una pieza enlazada sin ficha para la release.
