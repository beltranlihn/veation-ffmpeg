# veation-ffmpeg · rama mac-8.1-r475

FFmpeg n8.1.3-18-g46d899d7a0 para el .app de macOS (arm64) de VEATION, compilado desde fuente fijada en GitHub Actions
(macos-15): x264, x265 (8/10/12 bits), libvpx y snappy a los mismos commits que el ffmpeg.exe de Windows, estatico,
macOS minimo 12.0. `mac-r475/construir.sh` compila y arma el paquete de fuente; `mac-r475/comprobar.sh` mide lo que la
app necesita; `.github/workflows/mac-r475.yml` lo ejecuta y deja binario y fuente como artefactos.
