# Aurora en Linux

Aurora funciona en Linux x64 (Ubuntu 22.04 o posterior, o una distribución equivalente).

## Instalar desde una versión publicada

1. Descarga `Aurora-<versión>-linux-x64.tar.gz` y `checksums.txt` desde
   [Releases](https://github.com/kaz-py/auroraMusic/releases).
2. Comprueba el archivo:

   ```bash
   sha256sum -c checksums.txt --ignore-missing
   ```

3. Instala las bibliotecas que necesita la app:

   ```bash
   sudo apt-get install libgtk-3-0 libsecret-1-0 libasound2 libopus0 libogg0 ffmpeg
   ```

   En Ubuntu 24.04, el paquete de audio se llama `libasound2t64`.

4. Extrae el archivo y abre la app:

   ```bash
   mkdir -p ~/aurora && tar -xzf Aurora-<versión>-linux-x64.tar.gz -C ~/aurora
   ~/aurora/aurora_music
   ```

Para actualizar, repite estos pasos con la versión nueva. En Linux, Aurora no tiene
actualizador integrado.

## Compilar desde el código

```bash
sudo apt-get install clang cmake ninja-build pkg-config lld libgtk-3-dev liblzma-dev \
  libstdc++-12-dev libsecret-1-dev libjsoncpp-dev libasound2-dev libopus-dev libogg-dev
flutter pub get
flutter build linux --release
```

El resultado queda en `build/linux/x64/release/bundle/`. Usa Flutter 3.38.8, la misma
versión que la CI.

Las cuentas, la Jam en línea, Last.fm y Discord necesitan claves al compilar. Guárdalas
en un archivo JSON fuera del repositorio y pásalo con
`--dart-define-from-file=<archivo>`. Usa estas variables: `AURORA_SUPABASE_URL`,
`AURORA_SUPABASE_ANON_KEY`, `AURORA_LASTFM_API_KEY`, `AURORA_LASTFM_SECRET` y
`AURORA_DISCORD_CLIENT_ID`. Nunca subas ese archivo a Git.

## Requisitos

- **ffmpeg en el `PATH`**: hace falta para reproducir YouTube y los formatos que no son
  mp3, wav, ogg o flac.
- **Descargas**: usan `yt-dlp`, `ffmpeg` y `ffprobe` del sistema
  (`sudo apt-get install yt-dlp ffmpeg`), o la carpeta que elijas en Ajustes.
- **Llavero del sistema**: la sesión de tu cuenta y la de Last.fm se guardan con
  libsecret. Necesitas un llavero activo, como GNOME Keyring o KWallet.

## Diferencias con Windows

Funciona igual que en Windows:

- Búsqueda y reproducción nativa con ecualizador.
- DJ y cola continua.
- Biblioteca y descargas.
- Cuenta y sincronización.
- Amigos.
- Last.fm.
- Jam.

Discord muestra lo que escuchas si su app de escritorio está abierta, incluso en Flatpak
o Snap.

Duvet usa un socket local y busca `duvet-ipc` en `$XDG_RUNTIME_DIR`, `$TMPDIR` y
`/tmp`. Esas rutas no están confirmadas, porque no hay documentación pública de Duvet
para Linux.

En Linux no están disponibles:

- El reproductor de respaldo en WebView y la hoja «Revisar sitio». Si YouTube bloquea
  una canción, se muestra el error real.
- Los controles multimedia del sistema (MPRIS) y las teclas multimedia.
- La bandeja del sistema, cerrar a la bandeja y el inicio automático.
- Los enlaces `aurora://`. Para unirte a una Jam, escribe su código.
- El actualizador integrado y el actualizador de yt-dlp.

## Problemas conocidos

- No se ha probado el sonido en un equipo Linux real. La compilación se probó en WSL,
  que no tiene tarjeta de audio.
- Un test del proxy de audio (cliente que se va durante un vaciado pendiente) falla en
  Linux. Si una canción larga se corta, avísanos.
- Sin llavero activo, la app avisa de que no puede guardar la sesión y tendrás que
  iniciar sesión cada vez.
