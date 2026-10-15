# Aurora Music — guía para Claude

Lee también `AGENTS.md` (estilo, comandos) y `DESIGN.md` (estética). Este archivo
manda sobre `RETOMAR_AURORA.md` cuando se contradicen: el motor WebView quedó
reemplazado por el motor de audio InnerTube (15/10/2026, pedido del usuario).

## Qué es

Reproductor Flutter (Windows + Android) con estética propia «Atelier Sonoro»
(Newsreader + Plus Jakarta Sans, tonos tinta/marfil con acento de portada).
Funcionamiento de referencia: LIMusic (búsqueda de YouTube Music, radio/autoplay,
cola nativa), pero con la interfaz de Aurora. **No cambiar la estética.**

## Motor de audio (actual)

- `lib/sources/innertube_source.dart`: búsqueda de canciones en YouTube Music
  (InnerTube WEB_REMIX) y resolución de **solo audio**.
  Si la resolución falla, yt-dlp solo **extrae la URL** (fallback, un intento).
- **Streaming real en Android y Windows por igual**: el audio suena mientras
  llega. Nunca descargar el archivo completo antes de reproducir (causó
  bloqueos de yt-dlp).
- Reproducción nativa: Android `AndroidMusicAudio` (Media3, servicio en segundo
  plano); Windows `MusicAudio` (SoLoud + FFmpeg). Sin WebView en la reproducción.
- yt-dlp: descargas explícitas (audio y vídeo) y fallback de resolución.
- DJ: `lib/dj/` — IA propia y local: base de datos vectorial (drift/SQLite) con
  embeddings de pistas y perfil de gustos del usuario; ranking por similitud +
  diversidad (MMR). No usa recomendaciones de YouTube: YouTube solo da el audio
  (y la búsqueda para encontrar pistas reproducibles).

## Comandos (PowerShell, Windows)

```powershell
$flutter = 'C:/flutter/flutter/bin/flutter.bat'
& $flutter pub get            # si falla por symlinks: scripts/prepare_windows_plugins.ps1
& $flutter analyze
& $flutter test
C:/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe format lib test
& $flutter build apk --release
$env:PATH = "$PWD/build/build-tools/nuget;$env:PATH"; & $flutter build windows --release
```

## Reglas

- Nunca commitear ni imprimir claves, tokens, cookies, keystores ni `key.properties`.
  InnerTube se usa sin clave de API.
- `diseñoidea/`, `.agents/`, `skills-lock.json` y `DESIGN.md` son del usuario:
  no borrarlos ni incluirlos en commits salvo que lo pida.
- No hacer reset/clean/stash destructivo; hay trabajo sin confirmar.
- Mensajes de commit cortos en imperativo; `[skip ci]` si no debe correr CI.
  **Sin líneas `Co-Authored-By` ni atribución a Claude** en commits o PRs.
- No afirmar reproducción real basándose solo en tests simulados.

## Trabajo con subagentes

El agente principal orquesta: reparte tareas por áreas con dueños de archivos
claros (worktrees separados), integra, ejecuta analyze/test y builds, y hace el
commit final. Opus para motor/algoritmos; Sonnet para revisión, docs y builds.
