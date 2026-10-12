# Metadatos de Spotify

`lib/metadata/spotify/` adapta el proveedor de Nuclear
[plugin-something](https://github.com/NuclearPlayer/nuclear-plugin-something),
commit `d0229207d27c998a8ca63a05c09329396a673828`.

- `spotify_auth.dart`: HTTP con TLS del sistema, sin cookies, redirecciones ni logs;
  autorización anónima con TOTP SHA-1, período local de 30 segundos y servidor de
  900 segundos. Descarga el diccionario de rotaciones público usado por Nuclear;
  no incluye secretos codificados ni credenciales personales en el repositorio.
- `spotify_metadata_provider.dart`: consultas persistidas Pathfinder de Nuclear,
  búsqueda de canciones, artistas, álbumes y playlists, detalles y páginas.
- `spotify_models.dart`: entidades, mapeo de portadas/duración/artistas/álbum y
  canciones pendientes de coincidencia con una fuente de audio existente.
- `spotify_browser_controller.dart`: búsqueda, páginas, detalle y estados de UI;
  descarta respuestas de búsquedas antiguas y evita duplicados entre páginas.

## Uso y límites

`search(query, type:, limit:, offset:)` devuelve `SpotifyMetadataPage`;
`details(entity, offset:, limit:)` devuelve `SpotifyMetadataDetails`. Las páginas
exponen `nextOffset`/`hasMore`; no descargan automáticamente toda una playlist.
Una página vacía finaliza la navegación aunque el servidor anuncie más elementos.
Los detalles de artistas consultan biografía y canciones principales; no recorren
su discografía completa. Las canciones conservan título, artista, álbum, portada,
duración y URI de Spotify, con `spotifyMatchPending=true`, sin URL de audio.
La interfaz exige elegir una coincidencia del proveedor de audio de Aurora antes
de agregar/reproducir. Spotify no reproduce ni descarga audio.

El caché de respuestas dura cinco minutos y conserva como máximo 128 consultas;
las consultas idénticas en vuelo se comparten. Hay hasta tres solicitudes HTTP
concurrentes y cien consultas pendientes. El token anónimo se renueva antes de
vencer y una respuesta HTTP 401 permite un solo reintento con token renovado.
El diccionario de rotaciones se conserva una hora; los intentos están limitados
a cinco versiones por pase, con una sola recarga del diccionario. Las peticiones
tienen un límite de veinte segundos y las respuestas de cuatro MiB. Los errores
expuestos son genéricos y nunca incluyen respuestas HTTP, tokens o URLs TOTP.

Este mecanismo usa endpoints privados del reproductor web y los hashes de
consultas de Nuclear; Spotify puede cambiar autenticación, esquema o hashes sin
aviso. No requiere API oficial, cuenta del usuario ni Premium. La disponibilidad
regional, las restricciones del servicio y la correspondencia entre catálogos
pueden producir datos ausentes o ninguna coincidencia de audio. No se infieren
géneros, historial, favoritos ni estadísticas personales desde este proveedor.

## Licencia y pruebas

La adaptación conserva AGPL-3.0-only, atribución y texto completo en
`third_party/nuclear_spotify/NOTICE` y `LICENSE`, también incluidos como assets
para distribución. El código correspondiente está en este repositorio. Conservar
los avisos y cumplir la licencia al distribuir la adaptación.

`flutter test test/spotify_metadata_test.dart` utiliza transporte HTTP inyectado
con respuestas inventadas; no realiza llamadas a Spotify ni usa tokens reales.
Las pruebas cubren autenticación, expiración/401, cache, concurrencia, mapeo,
paginación, entradas inválidas, errores y estados obsoletos del controlador.
No se ha verificado la disponibilidad real de endpoints de Spotify.
