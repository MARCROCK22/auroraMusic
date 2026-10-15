# Aurora Music — guía para Claude

Lee también `AGENTS.md` (estilo, comandos) y `DESIGN.md` (estética). Este archivo
manda sobre `RETOMAR_AURORA.md` cuando se contradicen. Decisión final del usuario
(15/10/2026): el audio de YouTube suena en el reproductor oficial de
music.youtube.com dentro de un WebView invisible, con la interfaz de Aurora encima.

## Qué es

Reproductor Flutter (Windows + Android) con estética propia «Atelier Sonoro»
(Newsreader + Plus Jakarta Sans, tonos tinta/marfil con acento de portada).
Funcionamiento de referencia: LIMusic (búsqueda de YouTube Music, radio/autoplay,
cola nativa), pero con la interfaz de Aurora. **No cambiar la estética.**

## Motor de audio (actual)

- Búsqueda: `lib/sources/innertube_source.dart` (InnerTube WEB_REMIX: canciones,
  álbumes, artistas, vídeos, continuación). No volver a la búsqueda por DOM.
  `resolve()` devuelve `https://music.youtube.com/watch?v=<id>`; no extrae nada.
- Reproducción YouTube: `lib/audio_web/` (`WebMusicAudio` + `NativeWebMusicBridge`):
  WebView siempre montado en `aurora_shell.dart`, 1×1 y tapado, sin puntero/foco/
  semántica; solo se muestra como hoja cuando el sitio pide consentimiento/acceso
  («Revisar sitio»). Metadatos desde el `Track`; estado/progreso/fin desde el
  elemento multimedia. Anuncios: filtros `adblocker_webview` (solo Windows) +
  silenciar/omitir; no es garantía.
- Local: Android `AndroidMusicAudio` (Media3, servicio; además refleja el WebView en
  la sesión/notificación con bloqueos de CPU/Wi-Fi), Windows `MusicAudio`
  (SoLoud + FFmpeg) con EQ/espectro. `RoutedMusicAudio` elige un único motor.
- **Prohibido**: tokens PO, imitar clientes/UA, extraer URLs de audio de YouTube,
  saltarse restricciones del sitio (p. ej. reproducción en segundo plano de Premium).
- yt-dlp: solo descargas explícitas (audio y vídeo) e importación de listas.
- DJ: `lib/dj/` — IA propia y local: base de datos vectorial (drift/SQLite) con
  embeddings de pistas y perfil de gustos del usuario; ranking por similitud +
  diversidad (MMR). No usa recomendaciones de YouTube.
- Detalle: `docs/youtube_music_audio_engine.md`.

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
