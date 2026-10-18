# Letras

Código: `lib/lyrics/` (`lyrics_service.dart`, `lyrics_match.dart`) y `lib/ui/lyrics_panel.dart`.

## Antes (estado previo)

- Una sola fuente: LRCLIB `get` por artista + título (sin álbum ni duración), con
  coincidencia exacta tras una limpieza mínima.
- Caché en disco por pista que se leía primero: una letra equivocada guardada
  una vez no se corregía nunca; sin caché negativa (cada apertura repetía la
  petición).
- Fallos: ningún respaldo si `get` no acierta (títulos con «feat.», «- Topic»,
  remasters, japonés/acentos), duración ±2 s rechazaba letras buenas de otra
  edición, sin reintentos, sin elegir otra letra, desfase ±0,5 s solo durante la
  sesión, sin indicar el origen.
- La rama `aurora-letras-interactivas` (toque en línea para saltar, seek, arrastre)
  ya está integrada en el panel; no se modificó.

## Fuentes (verificadas con peticiones reales de baja frecuencia, 17/10/2026)

| Fuente | Uso | Estado |
| --- | --- | --- |
| LRCLIB `https://lrclib.net/api/get` | principal: sincronizada (LRC) y plana | operativa; abierta, sin clave. A veces responde 503 «server busy» (por eso hay reintentos con backoff) |
| LRCLIB `/api/search` | candidatos puntuados y «Buscar otra letra» | operativa (devuelve lista vacía si no hay) |
| lyrics.ovh `/v1/<artista>/<título>` | respaldo, solo letra plana | operativa; sin duración, por eso confianza baja |

No se usan Genius/Musixmatch ni scraping (sus términos lo impiden / piden clave).
Ninguna fuente requiere clave. Petición con
`User-Agent: Aurora/<versión> (https://github.com/kaz-py/auroraMusic)`, sin email,
usuario ni rutas locales; solo viajan artista, título, álbum y duración limpios.

## Flujo

1. Se limpian título/artista (`cleanTitle`, `cleanArtist`): fuera «(Official
   Video)», «[Lyrics]», «feat.», «- Topic», «VEVO», remasters; se usa el artista
   principal. Se conservan «live», «remix», etc. (importan para la puntuación).
2. Caché negativa vigente (<24 h) y sin «Reintentar» → «Sin letra disponible» sin
   red. Letra elegida/importada a mano → se usa sin pisarla.
3. **Red primero**: LRCLIB `get` → LRCLIB `search` (mejor puntuado, sincronizada
   preferida a igualdad) → lyrics.ovh. Timeout 3 s por petición, 2 reintentos con
   backoff 0,4/0,8 s ante timeout, 429 o 5xx; 404 y respuestas no JSON = «no hay».
4. La respuesta buena **reemplaza** la caché (corrige letras equivocadas antiguas).
5. Caché local solo de respaldo: si la red falla, o no hay resultado, se muestra
   la guardada («· guardada»). Si hay caché y la red tarda >3 s se enseña la
   guardada y se sustituye cuando llega la nueva. Si todo falla y no hay caché →
   error con «Reintentar» (no se cachea como «sin letra»).
6. Solo si todas las fuentes confirman que no existe se escribe la caché negativa
   (24 h). «Reintentar» la ignora.
7. Cambiar de pista (nueva carga o `dispose`) cierra las peticiones en curso y
   descarta el resultado; la reproducción nunca espera a las letras.

## Puntuación (`scoreLyricsCandidate`)

`0,45·título + 0,30·artista + 0,25·duración`, −0,30 si «live/remix/acoustic…»
no coincide con lo pedido. Acepta si título ≥0,6, artista ≥0,5, puntuación ≥0,65
y duración ≤30 s de diferencia. **Sincronía solo si la duración difiere ≤3 s**
(o se desconoce); si no, se usa el texto plano. Confianza: alta ≥0,85, media
≥0,70, baja el resto. Normaliza acentos latinos y compara kana/kanji tal cual.

## Caché

`<datos>/lyrics/<hash>.json` (no se guarda el id crudo ni rutas: hash del id +
título/artista normalizados). Máx. 400 archivos, LRU por fecha de uso. Desfase por
pista en `lyrics/offsets.json` (máx. 500). Sin migración SQLite.

## Panel

Estados: «Buscando letra…», «Sin letra disponible» (Reintentar, Buscar otra
letra, Importar LRC/TXT), origen en la cabecera («LRCLIB · sincronizada»,
«· guardada», «lyrics.ovh · texto plano»), copiar letra, tamaño A−/A+, desfase
±0,5 s recordado por pista, texto plano desplazable con aviso. Toque en una
línea = salto a ese instante vía `AppController.seek`; en la Jam sigue la
posición del reproductor y el salto depende de los permisos que ya aplica el
controlador (no se tocó la Jam).

## Pruebas

`test/lyrics_cascade_test.dart` (limpieza, puntuación, cascada con cliente HTTP
falso: éxito, 404, timeout, 503, respuesta rara, caché positiva/negativa,
corrección de caché, red lenta, cancelación, desfase), `test/lyrics_behavior_test.dart`
(servicio y panel). Las pruebas contra la red real no forman parte de la suite.

## Pendientes

- Traducción (modo «Traducción» sigue sin implementar).
- User-Agent con versión fija en código (`LyricsService.userAgent`).
- Sin verificación visual en pantalla de los cambios del panel.
