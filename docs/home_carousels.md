# Filas de música en Inicio

`lib/ui/home_music_page.dart` compone Inicio fuera del shell. Los callbacks conservan la navegación a búsqueda, descargas, favoritos y playlists. Muestra recientes, recomendaciones con su motivo, resultados del descubrimiento solicitado, playlists del usuario y canciones de la biblioteca en filas horizontales. Solo aparecen filas que tengan datos; no se construyen álbumes o artistas ficticios ni se repite un destacado de recientes.

`lib/ui/horizontal_music_row.dart` reúne los controles de cada fila: desplazamiento táctil, arrastre con ratón, trackpad horizontal, Shift + rueda, flechas visibles cuando hay contenido fuera de la vista, scrollbar y teclas izquierda/derecha/Inicio/Fin cuando la fila tiene foco. Usa el manejo de punteros nativo de Flutter: la rueda vertical sigue desplazando la página. El ancho fijo de los elementos permite calcular exactamente los extremos incluso antes de construir todas las tarjetas.

`PlaylistShelf(horizontal: true)` adapta las playlists a Inicio; el valor por defecto conserva la disposición de Biblioteca. `DjPanel(showRecommendations: false)` mantiene filtros y controles del DJ y descubrimiento en Inicio, mientras `HomeMusicPage` representa sus resultados horizontalmente. Los valores por defecto mantienen el comportamiento de otras pantallas.

Las tarjetas usan portadas y metadatos de Aurora. Si no hay portada, muestran el icono existente. La reproducción usa la cola y proveedores actuales; una canción importada de Spotify pendiente abre el selector de coincidencias existente. No se añadieron dependencias, migraciones ni fuentes de datos.

`test/home_carousels_test.dart` comprueba arrastre táctil y con ratón, teclado, extremos, flechas, ausencia de controles innecesarios, rueda vertical/horizontal/Shift, acciones de playlists y reproducción, estados vacíos y layout de 320 dp con texto al 200 %. Las capturas de fixtures sin red están en `build/ui-review/home-carousels-1440.png` y `home-carousels-320.png`; cargan las tipografías del repositorio. La integración de navegación en el shell y las compilaciones se verifican sobre la rama integrada.
