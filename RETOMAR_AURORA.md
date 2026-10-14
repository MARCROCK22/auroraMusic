# Contexto para retomar Aurora Music

Actualizado: 13 de octubre de 2026. El usuario pidió guardar el contexto porque se está quedando sin tokens. **La última migración sigue en desarrollo; no afirmar que está terminada, compilada o publicada.**

## Instrucción para la próxima conversación

> Lee `AGENTS.md` y `RETOMAR_AURORA.md` del repositorio actual. Retoma la integración pendiente con agentes en worktrees independientes. Conserva mis cambios. Quiero Aurora como en la segunda imagen: interfaz nativa de audio, sin vídeo visible, streaming mediante WebView y yt-dlp solo para descargas explícitas. Revisa las ramas pendientes, integra sin perder trabajo y verifica reproducción, pruebas y compilaciones. No me muestres toda la página de YouTube Music como reproductor principal.

## Requisito vigente: tiene prioridad sobre peticiones anteriores

- Flutter conserva Inicio, Buscar, biblioteca, artistas, playlists, favoritos, DJ, cola, reproductor, controles, ajustes y archivos locales.
- **Aspecto objetivo:** pantalla anterior de Aurora «AHORA SUENA», portada grande, título, artista, letras, cola, barra de progreso, aleatorio/anterior/reproducir/siguiente/repetir, favoritos, playlists, EQ, sueño y volumen.
- Referencia exacta guardada en [aurora-player-objetivo.png](docs/contexto/aurora-player-objetivo.png). Es la segunda imagen que proporcionó el usuario.
- La primera imagen [aurora-webview-reemplazar.png](docs/contexto/aurora-webview-reemplazar.png) muestra la página completa de YouTube Music; **NO es el resultado deseado**.
- Streaming de YouTube Music mediante WebView/viewer, con sus controles conectados a la cola de Aurora. **No volver a usar yt-dlp para resolver streams.**
- yt-dlp/nightly sigue únicamente para descargas explícitas. Ya existe un descargador de vídeos separado; conservarlo. No iniciar descargas automáticamente al reproducir.
- Sin vídeo visible. Distinguir ocultar su presentación de garantizar que la red transporte exclusivamente audio: eso último aún no se ha probado para todas las canciones.
- Mantener sesiones/cookies normales del componente. Sin suplantar UA, copiar credenciales, evadir login/DRM/Premium o prometer quitar restricciones de YouTube.
- Conservar el filtro solicitado `adblocker_webview` mediante su API de filtros. No afirmar que elimina anuncios insertados en los streams.
- Probar primer plano, segundo plano y pantalla apagada. No afirmar reproducción audible o universal a partir de tests simulados.
- El usuario pidió **usar agentes siempre**, modelos eficientes para tareas simples y razonamiento técnico para las complejas; ramas y worktrees separados. No pedir confirmaciones rutinarias.

## Repositorio y protección del trabajo

- Ruta: `C:/Users/pc1/orca/projects/reproductor-flutter`.
- PowerShell; rama `main`; HEAD al crear este archivo: `bf22126`.
- GitHub: `kaz-py/auroraMusic`. Los cambios actuales no se han subido ni publicado.
- `diseñoidea/` sigue **sin seguimiento y pertenece al usuario**: no eliminar, modificar ni incluir accidentalmente en commits.
- Hay cambios de integración sin confirmar en `main`; no sobrescribirlos ni hacer reset/clean/stash destructivo.
- Archivos modificados en `main`: `lib/audio/android_music_audio.dart`, `lib/main.dart`, `lib/ui/aurora_shell.dart`, `lib/ui/offline_settings_panel.dart`, `lib/ui/studio/studio_navigation.dart`.
- Nuevos archivos de integración pendientes: `lib/audio/routed_music_audio.dart`, `test/routed_music_audio_test.dart`.
- **El WIP de main referencia APIs y archivos todavía en ramas de agentes. No está listo para compilar hasta integrar esas ramas.**

## Qué ya existe e integración pendiente

La primera implementación de esta sesión abrió todo `music.youtube.com`. Se revisó e integró, pero después el usuario aclaró que quiere el reproductor nativo anterior. No confundir ambas etapas.

Ya integrados en main:

- `kaz-py/feat-explicit-video-downloads`, commit `3c93903`: descarga de vídeo explícita, progreso/cancelación, fuente Dart y método nativo Android.
- `kaz-py/feat-youtube-music-webview`, `6968981`: página oficial visible, navegación, errores, filtro y entorno WebView2.
- `kaz-py/refactor-official-music-routing`, `b46cb45`: aislamiento del antiguo resolvedor, preservación de locales/Jam, tests.
- Integración raíz `139251b`: navegación, ajustes, descarga persistente entre pestañas, guardia de cierre Windows, fixes y workflow NuGet.
- `kaz-py/feat-aurora-artists`, `3af5bc3`, merge `bf22126`: `lib/ui/artists_page.dart`, tres tests. Agrupa artistas reales de `Track`, muestra canciones y acciones; sin catálogo ficticio.

Ramas pendientes **consultar HEAD actualizado, los agentes pueden haber añadido otro commit de checkpoint**:

| Rama / worktree | Modelo | Trabajo y estado conocido |
| --- | --- | --- |
| `kaz-py/research-audio-only-web-engine` / `C:/Users/pc1/orca/workspaces/reproductor-flutter/research-audio-only-web-engine` | `gpt-6.1-sol`, high | `bb78291`: `lib/audio_web/web_music_audio.dart`, `web_music_bridge.dart`, siete tests y probe CDP. Pendiente checkpoint de documentación/portada. |
| `kaz-py/research-aurora-audio-routing` / `.../research-aurora-audio-routing` | `gpt-6.1-sol`, high | `5ef7877`: controller/source/core, arranque robusto, cola única, metadatos. Agregando callback de búsqueda mediante navegador. 90 tests específicos habían pasado. |
| `kaz-py/feat-web-music-metadata` / `.../feat-web-music-metadata` | `gpt-6-luna`, high | `821022e`: módulo de búsqueda y tests. Terminó; no pudo ejecutar tests en su worktree por falta de resolución de paquetes/bridge; **ejecutarlos al integrar**. |

No integrar a ciegas. Leer los diffs, revisar las APIs y conservar el trabajo raíz. Los agentes solo editaron sus archivos asignados. No necesitas crear otra copia del mismo trabajo.

## Contratos acordados y WIP raíz

- `AudioBackend`: getters por defecto `mediaActions`, `currentTrackMetadata` y método `updateTrackMetadata(Track)`. El agente de routing los añade a `lib/core/audio_backend.dart`.
- `WebMusicAudio extends AudioBackend`: `buildEngineView(showWebsite: false)`, `needsWebsiteAccess`, `adPlaying`, `title`, `artist`, `currentTrackMetadata`, `adBlocker`.
- Entrada web: únicamente `https://music.youtube.com/watch?v=<ID válido de 11 caracteres>`, sin headers ni URLs de medios extraídas. La página oficial reproduce y el puente lee/controla `HTMLMediaElement`.
- WebView permanece montada, cubierta y sin vídeo visible, detrás de los widgets de Aurora; acceso visible opcional para consentimiento/errores, también con vídeo oculto. Scripts de presentación/control no extraen `src`, tokens ni cookies.
- `WebMusicSource(delegate, audioOnly: true, metadataSearch: ...)`: `usesYouTubeWebAudio=true`, `usesOfficialYouTubeMusic=false` (este último significa el antiguo modo de página completa). Resuelve identificadores oficiales y archivos locales; no delega search/resolve en yt-dlp.
- `WebMusicMetadata`: `initialize() -> Future<bool>`, `activated`, `error`, `searching`, `tracks: List<Track>`, `search(query,{limit}) -> Future<List<Track>>`, `buildMetadataView()`, `dispose()`.
- Búsqueda usa una **segunda vista dedicada a metadatos**, activada al primer uso, para no interrumpir el audio. Lee el DOM público del sitio mediante `command('search', videoId: query, generation: revision)`; caché 5 minutos, operaciones serializadas y espera limitada. Reutiliza el mismo entorno WebView2 del motor.
- Revisar especialmente el parser de metadatos: deduplicación, límites, URL de portada HTTPS sin credenciales, errores visibles, resultados vacíos y cancelación. El agente rápido no pudo validar la suite todavía.
- Raíz creó `RoutedMusicAudio(native, web)` con un motor activo, estado/completion del motor seleccionado y controles únicos. Locales/no-YT usan Android Media3 o Windows SoLoud/FFmpeg existentes. Android adapta `updateTrackMetadata` y eventos nativos.
- `main.dart` ya selecciona wrapper + WebMusicAudio y fuente `audioOnly:true`, y maneja `ready=false` de arranque. **Falta instanciar y conectar WebMusicMetadata a fuente/wrapper/shell y su dispose.**
- Shell añadió navegación Artistas (índice12), mantiene vídeos11 y acceso opcional10; monta motor web sin reparentarlo. Revisar montaje y eventos de metadatos antes de probar.
- `AppController.canDownloadTrack(Track)` pendiente de integrar: no ofrecer descarga de audio YT que el backend no permite; conservar locales y descargas directas de otras fuentes. Vídeos yt-dlp van por otra pantalla.
- **Reutilizar `_showPlayer` en `lib/ui/aurora_shell.dart`**: ya contiene prácticamente la composición de la segunda imagen, no crear otra pantalla ni copiar la web. Revisar botón descargar de ese modal (aún usa la condición antigua) y disponibilidad de EQ/espectro para WebView. Portada/título/artista deben venir de datos reales.
- Raíz añadió guardia de cierre Windows para web activa, acceso/consentimiento desde error y explicación de búsqueda. Texto de búsqueda sigue diciendo biblioteca/enlace: actualizar cuando la búsqueda online del módulo esté validada.
- Corregir solicitud extra de inicio: no navegar dos veces al crear WebView. El agente ya eliminó el doble load inicial. `_playCurrent` también llama `audio.stop()` antes de cambiar pista; revisar si genera navegación innecesaria a home (wrapper intenta pause al cambiar web→web).

## Verificación real y límites conocidos

**Resultados de la base anterior, antes del WIP audio-only:**

- `flutter analyze --no-pub`: limpio, log `build/android-verification/audio-only-analyze.log`.
- `flutter test --no-pub --reporter expanded`: **345 tests pasaron**, log `audio-only-tests.log`. No atribuir estos resultados al código integrado audio-only aún incompleto.
- Android APK debug compiló: log `web-music-android-debug.log`. Windows release también compiló: `web-music-windows-release.log`. Ambos corresponden a la fase de página completa, no a la integración pendiente.
- Artistas: tres tests pasaron en rama del agente. Motor web: siete tests simulados pasaron. Routing: 90 tests específicos pasaron antes del último callback de búsqueda.

**Emulador real disponible:**

- AVD `Aurora_Verification`, dispositivo `emulator-5556`, x86_64 API36.1, arrancado headless con `-no-audio`. App `com.aurora.aurora_music`, WebView Android134.0.6998.135.
- App instalada todavía corresponde al modo anterior de sitio completo. No está instalada la nueva UI de audio.
- En página oficial se cargó «Que Se Mueran», Romeo Santos, ID público `6geljA2OZSY`, duración251s. DOM real: VIDEO, readyState4, paused=true, currentTime0, videoWidth/Height0. Esto prueba acceso al elemento/metadatos; **no prueba reproducción audible, streaming completado ni pantalla apagada**.
- El probe exacto del puente con la configuración anterior devolvió `playBlocked` y `mediaError=0`. El agente ajustó `mediaPlaybackRequiresUserGesture=false` para las acciones explícitas desde botones Flutter. **Recompilar, instalar y verificar que ese ajuste funciona de verdad.**
- Los taps exploratorios en la página antigua no consiguieron avanzar currentTime; no presentarlos como prueba de audio.
- Reproducción de YouTube en segundo plano y pantalla apagada **no está verificada**. Probar y documentar restricciones reales, sin inferir éxito de un temporizador.
- Android nativo pudo mostrar `AudioNotInitialized`: arranque tenía lecturas/migración de descargas antes de `audio.initialize` dentro de un solo try. Agente routing separó inicialización; verificar error real y reproducción local después de integrar.

Herramientas para observar sin imprimir secretos:

- ADB: `$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`.
- Debug WebView proceso4410 al guardar contexto, socket `webview_devtools_remote_4410`; puede cambiar al reinstalar/reiniciar. Forward existente `tcp:9223`.
- `http://127.0.0.1:9223/json/list`, Python `websocket-client` disponible. Usar `suppress_origin=True` para conectar DevTools local.
- Probe agente `test/audio_only_engine_cdp_probe.py --run-bridge --action snapshot|play|pause`. Lee propiedades públicas; no imprime URL del stream/cookies.
- Script raíz ignorado `build/android-verification/inspect_music.py`: solo inspección; modo `navigate` abre el ID de prueba público. No usar mientras el usuario escucha otra pista.
- Capturas reales en `build/android-verification/aurora-youtube-music.png` y `music-watch.png` corresponden a web antigua; NO entregar como nueva UI.

## Entorno y builds

- Flutter `C:/flutter/flutter/bin/flutter.bat`:3.38.8 estable, Dart3.10.7. Usar el Dart de ese SDK para format, no el Dart de sistema.
- `flutter pub get` pidió soporte symlink Windows; se resolvió con junctions de plugins en el directorio generado siguiendo `scripts/prepare_windows_plugins.ps1`. No se cambió Developer Mode global.
- Dependencias actuales fijadas: `flutter_inappwebview:6.1.5`, `adblocker_webview:2.3.0`, `url_launcher:6.3.2`. Plugin Windows WebView2 necesita NuGet.
- NuGet6.12.1 en `build/build-tools/nuget/nuget.exe`, descargado de Microsoft y firma Authenticode válida. Añadir esa carpeta al PATH **solo del proceso** al compilar Windows. Workflow Windows ya recibió `NuGet/setup-nuget@v3`.
- Android usa Media3 únicamente para fuentes nativas/locales; no enviar audio por MethodChannel. Bundle Python/QuickJS/FFmpeg y yt-dlp se conservan por descargador explícito.

## Coordinación de agentes para retomar

Se aplicaron skills `orchestration`, `ponytail` y `design-craft`; usar la CLI real de Orca para este run, no fingir agentes.

- Ejecutable: `C:/Users/pc1/AppData/Local/Programs/orca/resources/bin/orca.exe`.
- Run actual: `run_1268b1cfe8b5`.
- Research original `ctx_f6cd81d8577a` terminó y se reutilizó su terminal para implementar motor; su primer informe era sobre la petición anterior y hay que sustituir esa conclusión por el prototipo posterior.
- Motor actual: `ctx_0d737e2ee613`, task `task_abb4eb3e904a`, terminal `term_d19f8da7-e06e-4618-9ee5-544eba463356`.
- Routing: `ctx_07538d24593e`, task `task_b287581c2548`, terminal `term_b1da668e-631c-42c8-b7de-0bf218254840`.
- Artistas `ctx_fe73fb29a262` y metadatos `ctx_563204a39941`: terminaron y sus terminales ya se liberaron; ramas/worktrees conservados.
- Se envió a los agentes todavía activos la petición de cerrar trabajo con checkpoint y reporte, sin añadir nuevas tareas. Al retomar, `orchestration check --run ... --json`, leer cada mensaje, liberar únicamente workers ya terminados y hacer ack de la entrega.
- Consultar `orchestration worker-list --run ... --json` antes de crear otros editores. No editar los mismos archivos desde dos agentes.

## Próximos pasos concretos

1. Leer git status, este archivo y las novedades de agentes; guardar sus commits y liberar terminales terminadas.
2. Revisar los diffs de motor/routing/metadatos. Integrar sus ramas sin sobrescribir cambios WIP raíz; evitar cherry-pick parcial que pierda los últimos arreglos.
3. Conectar metadata.search a WebMusicSource, montar su vista de forma persistente/lazy, disponerla correctamente y actualizar textos de búsqueda.
4. Reutilizar el reproductor anterior de la segunda imagen para audio web y local; no abrir toda la web al tocar una canción. Verificar portada y controles reales, no fingidos.
5. Ejecutar format, analyze, toda la suite (incluidos metadatos y wrapper), APK debug y Windows release. Corregir fallos reales.
6. Instalar en emulador y probar streaming desde controles de Aurora; progreso, pause/resume/seek/cambio de pista y transición web↔local. Probar búsqueda mientras suena sin interrupción. Observar bytes si se va a afirmar audio-only de red.
7. Probar foreground/background/pantalla apagada; documentar exactamente lo que funcione y lo que no. Tomar captura **real de la interfaz Aurora objetivo y su cola**.
8. Revisar descargas explícitas/cancelación y que yt-dlp no vuelva a streaming. Actualizar documentación y resumir cambios/limitaciones honestamente.

## GitHub y releases

- Última release publicada previamente: `v1.0.5`, https://github.com/kaz-py/auroraMusic/releases/tag/v1.0.5; Windows ZIP y APK Android firmado. `pubspec` sigue1.0.5+6.
- Secrets de firma ya se configuraron en la sesión previa: `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Verificar solo nombres/existencia si se publica; no mostrar valores, no reemplazar identidad de firma.
- **La integración actual no está publicada.** No subir APK anterior como si contuviera esta nueva UI. Primero terminar y probar.
