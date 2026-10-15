# Motor de audio de YouTube: reproductor oficial en WebView oculto

Decisión del usuario (15/10/2026, definitiva): todo el audio de YouTube suena en el
reproductor **oficial** de `music.youtube.com`, dentro de un WebView completamente
invisible, con la interfaz nativa de Aurora encima. Motivo: la extracción nativa
(`youtube_explode_dart`) quedaba cortada por YouTube tras ~1 MiB (exigencia de
tokens PO) y yt-dlp recibía HTTP 429. Aurora **no** genera tokens PO, **no** imita
clientes ni cambia el user agent y **no** extrae URLs de audio de YouTube.

## Piezas

| Pieza | Papel |
| --- | --- |
| [`InnerTubeSource`](../lib/sources/innertube_source.dart) | Búsqueda (canciones, álbumes, artistas, vídeos, continuación). `resolve()` devuelve `https://music.youtube.com/watch?v=<id>`; local → archivo; otras URLs → error explícito. Sin precarga. |
| [`RoutedMusicAudio`](../lib/audio/routed_music_audio.dart) | Un único motor activo: páginas `music.youtube.com` → web; todo lo demás → nativo. Solo la finalización del motor activo avanza la cola. |
| [`WebMusicAudio`](../lib/audio_web/web_music_audio.dart) | `AudioBackend` sobre la página oficial. Órdenes serializadas con generación por pista; estado observado cada 500 ms. |
| [`NativeWebMusicBridge`](../lib/audio_web/web_music_bridge.dart) | `flutter_inappwebview` 6.1.5, política de navegación, filtros de anuncios y el script de página (`webMusicMediaScript`). |
| [`aurora_shell.dart`](../lib/ui/aurora_shell.dart) | Monta el WebView una sola vez, en la misma posición del árbol. |

Los archivos locales siguen en Android Media3 (`AndroidMusicAudio`) y Windows
SoLoud + FFmpeg (`MusicAudio`), con ecualizador y espectro. En canciones de YouTube
`supportsEqualizer` y `supportsVisualization` son falsos y la interfaz lo indica.

## Nunca se ve la página

- El WebView está siempre montado (no `Offstage`: seguiría sin pintar) en una caja
  de 1×1 en la esquina, tapada por un cuadro opaco, con `IgnorePointer`,
  `ExcludeFocus` y `ExcludeSemantics`. CSS oculta además el `<video>`.
- No hay ningún botón que muestre el sitio durante el uso normal (se quitó la
  entrada «Acceso a YouTube Music» del menú).
- Solo si el sitio exige algo al usuario (página de consentimiento, inicio de
  sesión, verificación o un bloqueo de gesto) Aurora muestra un aviso en español
  con **Revisar sitio**. Ese botón agranda el mismo WebView como hoja sobre Aurora
  (sin reparentarlo); **Listo** la oculta y vuelve a intentar la canción.
- El inicio de sesión de Google dentro del WebView sigue bloqueado por la política
  de navegación existente: Google no admite ese acceso embebido.

## Órdenes y errores (antes «El sitio no pudo aplicar ese control»)

La causa del síntoma A era `play()` en carrera contra 4 s, colapsado en
`commandFailed`. Ahora el script de página:

- espera eventos reales `playing`/`timeupdate` con el elemento sin pausar, con un
  límite de 20 s (`playTimeout`); la llamada Dart tiene 5 s de margen extra;
- ante `AbortError` (el sitio cambió la fuente) vuelve a buscar el elemento,
  espera `loadeddata` y reintenta una vez;
- distingue `NotAllowedError` (`playBlocked`, pide revisar el sitio) y
  `TimeoutError` (`playTimeout`, basta con pulsar reproducir);
- solo busca posición con `readyState >= 1`; si no, la aplica en `loadedmetadata`;
- en los mensajes solo incluye nombres de error de una lista cerrada
  (`AbortError`, `NotSupportedError`, …), nunca mensajes, URLs ni DOM.

La espera inicial a que aparezca el elemento multimedia está acotada (30 s). Si el
sitio reproduce solo al navegar sin intención de Aurora, se pausa. No hay
reintentos automáticos de flujo: la recuperación del controlador ignora el motor web.

## Anuncios (sin garantías)

1. Filtros de red de `adblocker_webview` (EasyList/AdGuard) en la intercepción
   nativa, con dominios de YouTube/Google protegidos. **Solo Windows**: en Android
   la intercepción se desactiva por un ANR observado del plugin 1.1.3.
2. Si se muestra un anuncio (`.ad-showing`/`.ad-interrupting` en el reproductor),
   la página silencia su elemento multimedia, pulsa el botón «Omitir» del propio
   sitio en cuanto está visible y habilitado, y quita el silencio al terminar.
3. Aurora muestra «Anuncio · tu canción sigue después» en lugar del artista, no
   actualiza posición/duración con las del anuncio y nunca cuenta su final como fin
   de canción.

Los selectores de anuncios dependen del DOM del sitio y pueden cambiar.

## Metadatos y controles del sistema

Título, artista, álbum y portada salen del `Track` de Aurora (InnerTube); posición,
duración y fin, del elemento multimedia. Windows: `MediaControls` (SMTC) escucha el
`RoutedMusicAudio`, así que refleja la reproducción web y envía
reproducir/pausa/siguiente/anterior/buscar al controlador. Android: el servicio
Media3 recibe `external` dos veces por segundo y expone ese estado en su sesión
(`SessionPlayer.getState()`); sus órdenes vuelven como acciones (`seek:<ms>`
incluido).

## Android en segundo plano / pantalla apagada

Causa probable de las pausas anteriores: durante la reproducción web el servicio
Media3 no estaba reproduciendo, así que no pasaba a primer plano y Android podía
congelar o matar el proceso al salir de la app. Ahora:

- la sesión Media3 refleja la reproducción web → notificación y servicio en primer
  plano mientras suena;
- el servicio toma un `PARTIAL_WAKE_LOCK` (renovado, caduca solo a los 10 min sin
  noticias) y un bloqueo Wi-Fi mientras la web reproduce;
- `mediaPlaybackRequiresUserGesture: false`; el plugin no llama a
  `onPause`/`pauseTimers` por sí mismo y Aurora tampoco; la prioridad del renderer
  queda en la predeterminada (importante aun sin ser visible).

Pendiente y fuera de alcance legítimo: con un user agent móvil, el sitio puede
pausar la reproducción en segundo plano para cuentas sin Premium. Aurora no falsea
la visibilidad de la página ni el user agent para evitarlo.

## Windows

- Perfil WebView2 persistente en `<soporte>/youtube_music_webview`, reutilizado.
- Salida limpia: con el motor montado, cerrar la ventana pasa por
  `_confirmWindowClose`, que desmonta el WebView, espera un frame y libera el
  `WebViewEnvironment` antes de permitir el cierre (el entorno vivo retenía el
  proceso y `WebView2Loader.dll`).

## Pruebas

- `test/audio_only_engine_test.dart`: puente falso; órdenes, timeout de play,
  nombres de error, bloqueo de gesto, consentimiento, anuncios sin finalización,
  autoplay, generaciones obsoletas, montaje oculto 1×1 sin entrada.
- `test/web_music_script_test.dart`: ejecuta el script real en Node con un DOM
  mínimo (se omite sin Node): espera de eventos, reintento tras `AbortError`,
  timeout, silencio/omisión de anuncios, búsqueda antes de metadatos.
- `test/routed_music_audio_test.dart` y `test/web_engine_shell_test.dart`:
  enrutado web↔local, espejo de sesión, hoja de consentimiento y «Anuncio».

Ninguna prueba contacta YouTube. **Requiere verificación en dispositivo**: sonido
real, anuncios, segundo plano/pantalla apagada y notificación en Android, SMTC y
salida limpia en Windows.
