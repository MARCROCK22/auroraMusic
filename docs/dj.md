# DJ personalizado

`lib/dj/recommendations.dart` contiene un recomendador local determinista y sus
filtros. El controlador conserva la coordinación de reproducción, persistencia,
cola y búsquedas en los proveedores de audio existentes. No usa IA ni claves.

## Señales reales

- Favoritos: afinidad de artista y géneros conocidos, peso 4 por canción.
- Pertenencia a una o más playlists: peso 1,5, contado una vez por canción.
- Historial reciente: peso `2,5 / (1 + posición / 4)` por artista y géneros.
  El historial guarda el último uso de cada canción, no la frecuencia.
- Una candidata incluida en playlists recibe 1,5 adicional; si ya estuvo en el
  historial pierde 2 puntos para favorecer variedad.
- Se seleccionan como máximo dos canciones por artista en cada lote. Se omite
  la canción actual, los favoritos ya conocidos y canciones pendientes de una
  coincidencia de audio. Sin señales, el orden estable es artista/título.

Cada resultado explica la señal más relevante: artista favorito, playlist,
escucha reciente o género conocido. No hay datos de saltos, finalizaciones ni
frecuencia; no se simulan. Los favoritos, playlists e historial que el usuario
modifica se reflejan al recalcular las recomendaciones.

## Filtros y actualización

`DjFilters` acepta inclusiones `artists`, `trackIds`, `genres` y exclusiones
`excludedArtists`, `excludedTrackIds`, `excludedGenres`. Una inclusión vacía no
restringe esa dimensión. Se acepta cualquiera de sus valores dentro de una
dimensión y deben cumplirse todas las dimensiones configuradas. Las exclusiones
siempre prevalecen. Artistas y géneros usan coincidencia exacta tras quitar
espacios externos y normalizar mayúsculas; canciones usan su ID exacto.

`AppController.setDjFilters` persiste preferencias en `SharedPreferences` bajo
`djFilters`, invalida búsquedas pendientes y descarta resultados descubiertos.
Los filtros se aplican al inicio, recomendaciones, descubrimiento y recarga del
DJ. Se conserva la cola ya elegida por el usuario y la reproducción actual;
cambiar filtros afecta nuevas incorporaciones. El encolado manual sigue siendo
una elección explícita y no está limitado por los filtros del DJ.
`refreshRecommendations` recalcula la lista local y renueva el descubrimiento
cuando hay un artista de referencia disponible.

`Track.genres` guarda únicamente géneros proporcionados por datos reales. Las
canciones anteriores se restauran con una lista vacía; se conserva la base de
datos y no necesita migración. No se infieren géneros a partir del título ni del
artista. Un filtro inclusivo de género descarta canciones sin géneros conocidos,
por lo que puede dejar las recomendaciones vacías.

## Cola y audio

La identidad compartida considera ID, URL canónica y URI de Spotify, incluso
cuando la URL ya apunta a una coincidencia de YouTube. Se impiden duplicados en
recomendaciones, descubrimiento, recargas y encolado manual concurrente. El DJ
conserva el límite de 24 canciones y dos búsquedas de descubrimiento por sesión.

`importSpotifyMetadataMatch(metadata, match, play: false)` conserva las
descripciones, portada, álbum, géneros y URI de Spotify mientras toma el ID y
enlace de audio de una coincidencia seleccionada del proveedor existente. Solo
acepta una fuente local o HTTPS de YouTube/youtu.be, nunca audio de Spotify. Una
coincidencia seleccionada por el usuario puede ser incorrecta; no se afirma que
el título/artista garantice identidad del audio.

Las pruebas usan proveedores simulados y cubren compatibilidad JSON, filtros,
persistencia, puntuación por géneros, invalidación, recarga y duplicados.
