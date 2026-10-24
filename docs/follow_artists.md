# Seguir artistas

Los artistas seguidos son **locales** (Last.fm no tiene API para
seguir artistas). Código en `lib/follow/`; interfaz en `lib/ui/follow_widgets.dart`.

- Datos: tablas `followed_artists` y `new_releases` (esquema v3 de
  `LibraryDatabase`; la migración v2 -> v3 solo añade tablas).
- `FollowService.follow(name, browseId?)`: sin `browseId` (reproductor, biblioteca)
  busca al artista en YouTube Music por nombre exacto normalizado.
- Novedades: `refreshIfDue()` (se llama al abrir la app) consulta la página de
  artista (`InnerTubeSource.artistPage`, WEB_REMIX `browse`, sin clave) de los
  seguidos cuya última comprobación tiene más de 12 h; 3 peticiones a la vez,
  20 s de timeout, un fallo no afecta a los demás. La primera consulta de un
  artista fija la línea base y no anuncia nada.
- Reproducir una novedad: `NewRelease.entry` es un `SearchEntry` de álbum que
  abre `AppController.openSearchEntry` (la ficha de búsqueda ya reproduce).

## Enganche del DJ

- `followedArtistKeysProvider` (`follow_providers.dart`) o
  `FollowService.followedArtistKeys`: `Set<String>` con cada nombre en minúsculas
  y con `coherenceNorm`; coincide con `djPrimaryArtist(track)`.
- `followedArtistBonus(track, keys)` (`follow_boost.dart`) devuelve
  `followedArtistBoost` (0.12) para pistas de seguidos, 0 si no. Es un sesgo
  suave de ranking.
- Conectado hoy: `AppController.followedArtistKeys` (callback que pone
  `AuroraShell._startFollow`) se suma en el `adjust` de `rankDjCandidates`
  (`app_controller.dart`). No toca el filtro de coherencia, el tope por artista
  ni la memoria anti-repetición, que siguen aplicándose después/aparte.
- Si el agente del DJ reescribe esa llamada, basta con conservar
  `+ followedArtistBonus(t, followedArtistKeys())` dentro de `adjust`.
