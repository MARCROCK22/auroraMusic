# Interfaz de música

Las pantallas conservan el tema, navegación y controles de Aurora. La jerarquía de portadas, colecciones y panel de reproducción toma como referencia las aplicaciones de música de escritorio sin copiar marcas ni gráficos.

- `lib/ui/artwork.dart`: portada compartida, resolución limitada y fallback cuando falta una imagen o falla su carga.
- `lib/ui/playlist_shelf.dart`: tarjetas de playlists reales; collage con cuatro canciones o portada del primer tema, y acceso a la lista. Usado en Inicio y Biblioteca.
- `lib/ui/dj_panel.dart`: recomendaciones con explicación, actualización, controles del DJ y descubrimiento existente de YouTube.
- `lib/ui/dj_filters_panel.dart`: selección de artistas, canciones y géneros de la biblioteca. Los géneros ausentes se explican, las exclusiones existentes se conservan y las inclusiones combinan sus dimensiones.
- `lib/ui/spotify_browser_panel.dart`: selector de entidades, portadas, detalles, paginación y estados de búsqueda/carga/error. `SpotifyBrowserController` conserva el estado y las consultas fuera de los widgets. El diálogo de coincidencias pide elegir audio de YouTube antes de agregar metadatos a la cola; no reproduce URLs de Spotify.
- `lib/ui/aurora_shell.dart`: navegación y composición de estas pantallas, búsqueda de audio y biblioteca.
- `lib/ui/queue_panel.dart`: cola y reproducción; reutiliza portadas y muestra duración con el artista para dar espacio a los controles en pantallas pequeñas.

Las tarjetas, recientes y recomendaciones muestran datos de la biblioteca; no se agregaron colecciones ficticias. Las pruebas usan fixtures sin cuentas ni llamadas reales a Spotify y verifican acciones, paginación, estados y layouts a 320 dp con texto al 200 %. `test/ui_test.dart` genera capturas de Inicio en `build/ui-review/home-1440.png` y `home-320.png` con la biblioteca de prueba.

También se generan `dj-1440.png`, `dj-320.png`, `spotify-search-800.png` y `spotify-details-320.png`. Las capturas cargan las tipografías del repositorio y Material Icons. Los títulos largos de recientes reservan altura para texto ampliado. Las capturas de Spotify son del componente con fixtures y un tema oscuro de prueba; no usan un catálogo ni una cuenta personal.

La comprobación por widgets no certifica audio físico, Bluetooth ni la presentación nativa en un dispositivo Android. Esas comprobaciones requieren hardware.
