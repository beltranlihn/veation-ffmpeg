# notices/: avisos de licencia revisados a mano

Una carpeta por cada pieza cuyo código acaba dentro de `ffmpeg.exe` / `ffmpeg` (las de `rol:fuente`
del lock, más el runtime del toolchain de Windows: `mingw-w64` y `gcc`).

- `pieza.conf`: nombre visible, licencia (texto y SPDX) y `textos=`, las rutas **dentro del fuente** de
  los archivos de licencia, NOTICE y PATENTS. `ruta#cabecera` toma solo el primer comentario `/* … */`
  del archivo (cabeceras sin archivo de licencia aparte, como nv-codec-headers).
- `REVISADO`: el sha256 de cada texto **después de leerlo**. Empieza en `PENDIENTE`.

`tools/avisos.mjs textos` extrae esos textos del fuente EXACTO de la versión del lock (los mismos
archivos que van al paquete de fuente), así que lo que se publica en `FFMPEG-NOTICES.txt` es literal.
Cada vez que se ejecuta deja en `out/avisos/revision.txt` los sha256 de hoy:

1. la primera vez (o tras subir una versión), leer cada texto en `out/avisos/licencias/<pieza>/`;
2. si el texto está bien recogido y no trae obligaciones nuevas, copiar su línea a `REVISADO`;
3. si una versión nueva cambia un texto ya revisado, la release se para (`--estricto`) hasta revisarlo.

`scancode-base.json` es la base revisada de ScanCode (`tools/scancode.sh`): las expresiones de licencia
que se aceptan en el fuente de cada pieza. Un hallazgo que no esté en la base para la release.
