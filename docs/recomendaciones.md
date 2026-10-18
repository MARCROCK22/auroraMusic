# Recomendaciones de Aurora (Jam y DJ)

## Fuentes de Spotify: qué se puede usar y qué no

Estado verificado leyendo el código del repo (no se llamó a Spotify en esta
entrega; ver «Sin verificar»).

| Fuente | ¿Disponible? | Notas |
| --- | --- | --- |
| Web API oficial `recommendations`, `related-artists`, `audio-features`, `audio-analysis` | **No** | Retiradas en nov. 2024 para apps nuevas. Aurora no tiene (ni debe guardar) claves de Spotify, así que no se usan. |
| Web API oficial con OAuth del usuario (top tracks/artists, guardados) | **No** | Exige registrar una app con client id; el repo no lo lleva. |
| `SpotifyMetadataProvider` (`lib/metadata/spotify/`): consultas del reproductor web con token anónimo | **Sí, ya existe** | Es el mecanismo que el usuario ya autorizó (adaptado de Nuclear). Operaciones: buscar canciones/artistas/álbumes/playlists, detalle de artista (top tracks), álbum y playlist. |
| Géneros por pista | **Casi no** | Los resultados de pathfinder rara vez traen `genres`; hoy salen del perfil local y de los géneros que ya traiga el `Track`. |
| Artistas relacionados | **No usado** | Existe en la respuesta privada del artista, pero leerlo supone ampliar el uso de esa interfaz; se decidió no ampliarlo. Se sustituye por «artistas del mismo género» (búsqueda de artistas por género). |

Límites y honestidad:

* La interfaz de pathfinder es privada: puede cambiar sin aviso. El proveedor
  falla con un error claro y el motor lo trata como «fuente caída» (cae a lo
  local; nunca se queda vacío).
* El token anónimo se obtiene como ya hace `spotify_auth.dart` (no se tocó).
  Esta entrega **no amplía** ese acceso: solo llama a `search` y `details` del
  proveedor existente.
* Spotify solo aporta **metadatos**; el audio siempre sale de YouTube Music.
* ISRC: el modelo `Track` y las consultas del repo no lo exponen y YouTube Music
  no permite buscar por ISRC, así que el emparejamiento no lo usa.

## Emparejamiento Spotify → YouTube Music

`lib/metadata/youtube_match.dart`.

1. Busca `título + 2 primeros artistas` primero en *canciones* y, solo si nada
   llega al umbral, en *vídeos* (InnerTube `search`, ya existente).
2. Puntúa cada candidato (0–1): título 45 % (Dice de tokens sobre el título
   normalizado: sin `feat`, paréntesis, «remastered», acentos; tolera 1 errata),
   artistas 30 % (principal 70 %, resto 30 %; también vale «Artista - Canción»
   en el título o el canal «- Topic»), duración 20 % (≤3 s = 1; 8 s = 0,5; ~30 s = 0;
   más de 15 s de diferencia resta 0,15), álbum 5 %.
3. Penaliza −0,25 por etiqueta que el candidato trae y el original no: live,
   cover/tribute, karaoke, sped up/nightcore/8D, slowed/reverb, remix/mashup,
   acoustic. Pequeño bono por «Topic»/VEVO/«official audio».
4. Sin coincidencia de artista o título < 0,4 no hay candidato. Umbral de
   aceptación 0,62; la confianza se devuelve en `YoutubeMatch.confidence`.
5. Caché en SharedPreferences (`ytMatchCache`, 500 entradas; los fallos se
   recuerdan 1 día). No hizo falta migración de SQLite (sigue en v2).

Resultado real (ejecutado el 17/10/2026 con `LIVE_YT=1`, ver «Probar»): 6 de 6
canciones correctas (Blinding Lights, Despacito Remix, Bohemian Rhapsody
remaster, Creep, Hotel California, La Bachata; confianza 0,91–0,95) y una pista
inexistente rechazada correctamente.

## Motor de sugerencias

`lib/dj/suggestions_api.dart`, firma estable `getSuggestions(SessionContext)`.

* **Semillas**: perfil local (`buildTasteProfile`: favoritos, listas, historial
  y señales completó/saltó con decaimiento de 14 días; repetir suma). Si los
  `Track` traen géneros de Spotify, entran como características `g:`.
* **Candidatos** por cubo (cuotas configurables en `mix`): similar 50 %,
  adjacent 30 %, discovery 15 %, classics 5 %, más la radio de YouTube de la
  pista actual (`extraCandidates`, cubo `radio`, sin cuota).
  `spotifyRecSources()` (`lib/metadata/spotify_recs.dart`) los alimenta con
  Spotify y los empareja con YouTube: top tracks de tus artistas, artistas del
  género que más escuchas, un género fuera de tu burbuja (playlist «X
  essentials») y playlists de clásicos.
* **Ranking**: relevancia (coseno con el perfil + prior + continuidad + modo) −
  novedad (memoria) − penalizaciones; selección MMR con tope por artista
  (⌈límite/5⌉), género (40 %) y década (50 %, deducida de géneros/álbum/título;
  `Track` no guarda año) y enfriamiento de artista; bono de cuota por cubo;
  **exploración** ε = 0,2 (muestreo softmax) + ruido; semilla distinta por sesión.
* **Memoria anti-repetición** (`lib/dj/reco_memory.dart`): últimas 300 pistas
  recomendadas, clave `título normalizado|artista`, ventana de 7 días, en
  SharedPreferences (`recsMemory`). Si el pool no alcanza, la ventana se relaja
  (100 % → 50 % → 25 % → 0 %) y la penalización de novedad prefiere lo menos
  reciente; nunca se devuelve vacío mientras haya algo.
* **Grupo**: con N participantes el turno de cada pick rota (round-robin,
  `Suggestion.forParticipant`), y hay bono de afinidad si gusta a ≥2 personas.
* **Razones**: «Porque escuchas X», «Artistas parecidos a X», «Descubrimiento»,
  «Un clásico imprescindible», «Radio de YouTube», «De tu biblioteca».
* **Privacidad (Jam)**: cada dispositivo calcula con su perfil; solo se publican
  videoId + título/artista + razón (`JamSuggestionAdapter`, máx. 5 por persona
  y minuto, límites del servidor intactos).
* El DJ personal sigue siendo local; las fuentes de red (YouTube/Spotify) solo
  las inyecta quien construye el `SuggestionsApi` (la Jam).

## Integración

```dart
final api = SuggestionsApi(
  sources: spotifyRecSources(
    catalog: ProviderSpotifyCatalog(SpotifyMetadataProvider()),
    matcher: YoutubeMatcher(
      search: (q, k) async => (await innerTube.searchPage(q, k)).tracks,
    ),
  ),
);
JamSuggestionAdapter(related: ..., seeds: ..., local: ...,
    api: api, taste: () => ParticipantTaste('self', profile));
```

Pendiente de cablear en `AppController`/`JamController` (fuera de mis rutas):
crear el `api` una vez (no por llamada) y pasarlo al adaptador; llamar a
`RecsMemory.shared.record([track], now)` cuando una pista se reproduce.

## Probar

```powershell
flutter test --no-pub test/recs_engine_test.dart test/youtube_match_test.dart test/recs_spotify_test.dart
$env:LIVE_YT='1'; flutter test --no-pub test/live_youtube_match_test.dart   # red real
```

## Sin verificar

* `ProviderSpotifyCatalog` contra Spotify real (token anónimo + consultas
  privadas): solo probado con catálogo falso.
* Calidad subjetiva de la mezcla con historial real de usuarios.

## Coherencia de artista (filtro anti «solo coincide el título»)

**Causa raíz del caso «Ado» → «Ado (Teledrama Theme Song)»** (verificado en el
código; reproducido en `test/coherence_test.dart`): las fuentes de descubrimiento
buscan por TEXTO el nombre del artista (`'$seed songs'` y `djDiscoveryQueries` en
`app_controller.dart`; la radio de YouTube también mezcla pistas ajenas) y aceptan
cualquier resultado. El motor solo medía similitud de vectores y los tokens del
título entran en el vector, así que nada comparaba el ARTISTA del candidato con
el de la semilla. Además `ProviderSpotifyCatalog.artistTopTracks` tomaba el primer
artista de la búsqueda sin comprobar el nombre (ahora exige nombre igual).

**Cómo lo resuelven las plataformas** (conocimiento general, sin llamadas):
resuelven *entidades*, no texto: cada pista y artista tiene un ID (Spotify URI,
MusicBrainz MBID, YouTube channel/Topic); las pistas se unifican por ISRC o
huella de audio; la recomendación usa filtrado colaborativo (co-ocurrencia de
artistas en listas y sesiones), género, popularidad y embeddings de audio, nunca
«el título contiene la palabra». YouTube Music distingue canales oficiales y
«- Topic» (generados desde el catálogo del sello).

**Qué aplica en Aurora, gratis y sin claves:** comparación de artista normalizada
(acentos, mayúsculas, `feat./&/,`, « - Topic», japonés), colaboradores y `feat.`
del título, alias opcionales, género/década de los metadatos que ya haya
(Spotify solo lo ya autorizado; si no hay, se cae a lo local). No aplican ISRC,
MusicBrainz ni co-ocurrencia global (requieren red/datos externos).

**Implementación** (`lib/dj/coherence.dart`): `scoreCoherence(track, ctx)` →
`CoherenceResult(score 0..1, reason, hardReject)`; `CoherenceFilter.rank(
candidates, ctx)` acepta candidatos de cualquier cubo (radio incluida), ordena y
solo descarta rechazos duros (artista distinto, el nombre semilla solo en el
título y sin género común) mientras quede alguno; nunca vacía. `SuggestionsApi`
la aplica a todo (cola, DJ, Jam): `djCoherenceWeight` en la relevancia y
`Suggestion.coherence`/`coherenceReason`; el rechazo duro solo actúa si quedan
≥ `limit` candidatos limpios.
