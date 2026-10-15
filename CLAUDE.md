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
  (InnerTube WEB_REMIX), resolución de **solo audio** y `radio(seed)` (up-next).
  Si la resolución falla, delega en `YtDlpSource` (fallback) .
- Reproducción nativa: Android `AndroidMusicAudio` (Media3, servicio en segundo
  plano); Windows `MusicAudio` (SoLoud + FFmpeg). Sin WebView en la reproducción.
- yt-dlp: descargas explícitas (audio y vídeo) y fallback de resolución.
- DJ: `lib/dj/` — candidatos de radio + perfil de gustos local vectorial.

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
- No afirmar reproducción real basándose solo en tests simulados.

## Trabajo con subagentes

El agente principal orquesta: reparte tareas por áreas con dueños de archivos
claros (worktrees separados), integra, ejecuta analyze/test y builds, y hace el
commit final. Opus para motor/algoritmos; Sonnet para revisión, docs y builds.
