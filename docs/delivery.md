# Entrega integrada de Aurora

Los cambios se revisaron e integraron en `main` conservando los archivos originales de `dise?oidea/`. No se modific? el esquema SQLite ni se reemplaz? la identidad de firma.

## Trabajo separado

| Responsable | Rama | Resultado |
| --- | --- | --- |
| architecture | refactor/aurora-architecture | Separaci?n de biblioteca y recomendador; primera etapa compilada antes de las funciones |
| spotify | feat/spotify-metadata | Proveedor an?nimo de metadatos y pruebas simuladas |
| dj | feat/dj-recommendations | Puntuaci?n explicable, filtros, identidad de canciones y cola |
| ui | feat/music-ui | Componentes de biblioteca, b?squeda y estados |
| architecture | ci/android-signing | Workflows y restauraci?n segura de la firma existente |
| dj | feat/dj-discovery-ui | Navegaci?n DJ, tarjetas y gestos |
| ui | feat/home-carousels | Filas horizontales con datos reales |
| spotify | feat/lan-jam | Comunicaci?n LAN, cola compartida, QR y sincronizaci?n |
| coordinador | feat/jam-playback-isolation | Aislamiento y restauraci?n del reproductor personal |
| coordinador | feat/design-idea-flutter | Recursos originales, tema, Inicio, navegaci?n y controles nativos |
| ui | feat/design-idea-panels | Descargas y Letras fieles a la referencia |
| dj | test/design-idea-ui | Pruebas y capturas de la interfaz integrada |
| spotify | docs/aurora-delivery | Inventario visual y arquitectura final |

Cada tarea tuvo un worktree y una rama propios. Se revisaron los cambios antes de integrarlos mediante merges o cherry-picks identificables. Los worktrees anteriores ajenos a este trabajo se conservaron. La revisi?n adicional `test/jam-and-dj` no produjo cambios: ese agente agot? su disponibilidad; el coordinador realiz? la revisi?n y ejecut? las 41 pruebas focalizadas de Jam y DJ.

## Funciones

**Spotify** permite buscar canciones, artistas, ?lbumes y playlists, consultar detalles y paginar. Usa el mecanismo del plugin Nuclear: autenticaci?n an?nima del reproductor web, TOTP y consultas Pathfinder. Tiene cach?, concurrencia limitada, deduplicaci?n, renovaci?n y reintento controlado. Los tokens no se muestran. Para reproducir una canci?n se selecciona una coincidencia del proveedor de audio existente; Spotify solo aporta metadatos. Los endpoints privados pueden cambiar. Licencia y atribuci?n AGPL-3.0 del c?digo de referencia est?n en `third_party/nuclear_spotify/`. Detalles en [spotify_metadata.md](spotify_metadata.md).

**DJ** aparece inmediatamente debajo de Buscar. Deslizar a la izquierda omite y avanza; a la derecha guarda inter?s mediante favoritos, agrega a la cola y avanza. Tambi?n hay botones, bloqueo contra acciones repetidas y movimiento reducido. Punt?a artistas y g?neros presentes en favoritos, pertenencia a playlists y recencia del historial; penaliza repeticiones y limita la diversidad de artistas. No inventa frecuencia, omisiones ni finalizaciones, porque no existen esos registros. Los filtros incluyen/excluyen artistas, canciones y g?neros. Detalles en [dj.md](dj.md) y [dj_discovery.md](dj_discovery.md).

**Inicio** mantiene filas horizontales reales de recientes, recomendaciones, biblioteca y colecciones disponibles. Funcionan con tacto, arrastre, trackpad, Shift+rueda, flechas y teclado; la rueda vertical sigue moviendo la p?gina. No se crean colecciones vac?as ni canciones ficticias. Detalles en [home_carousels.md](home_carousels.md).

**Jam** se abre desde la navegaci?n o el panel de sesi?n. El anfitri?n elige su direcci?n LAN y crea la sala; los invitados escanean el QR desde Aurora, importan una imagen QR o pegan la invitaci?n. Windows permite imagen/invitaci?n; la c?mara Android se solicita solo al escanear. La cola compartida admite contribuciones, nombres, permisos de quitar/reordenar/omitir y l?mites contra duplicados y spam. El modo sincronizado requiere activaci?n de escucha en cada invitado: cada dispositivo resuelve su propio audio. El anfitri?n es autoritativo; los ajustes tienen tolerancia de 750 ms y pasos de hasta 500 ms cada 5 segundos. No se transmiten URLs extra?das, cookies, credenciales ni archivos de audio. La cola funciona aunque un tema no pueda reproducirse en un dispositivo. QR temporal, token aleatorio, expiraci?n, cierre, reconexi?n y mensajes validados. La sincron?a es aproximada y depende de las fuentes. Detalles en [jam.md](jam.md).

**Interfaz de referencia**: Inicio, Descargas y Letras se construyeron con widgets nativos, recursos originales empaquetados y las fuentes Newsreader/Plus Jakarta Sans/Material Symbols. No se usan WebViews ni capturas como fondos. Los datos de canciones, archivos, cola y reproducci?n proceden de Aurora; las capturas automatizadas usan fixtures sin red. Cinta/v?lvulas/432 Hz, medici?n DAC, CRC, USB, respaldo y traducci?n indican que est?n pendientes. Inventario y l?mites en [design_idea_implementation.md](design_idea_implementation.md).

## Firma

Los cuatro Repository Secrets Android se actualizaron con GitHub CLI autenticado el 12 de octubre de 2026 en `kaz-py/auroraMusic`, usando la keystore existente y validando su clave localmente. No faltan secretos Android: `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Se administran en Settings ? Secrets and variables ? Actions. El workflow valida presencia, restaura el archivo con ACL protegida en el runner y lo elimina siempre. Windows conserva ejecutables sin firma Authenticode. Ver [ci_signing.md](ci_signing.md).

## Verificaci?n

El an?lisis integrado no presenta problemas. Las compilaciones Windows release, Android ARM64 debug y Android ARM64 release se ejecutaron; el APK release supera `apksigner verify`. Los scripts de firma pasan los casos de secretos ausentes, Base64 inv?lido, ACL, restauraci?n y limpieza. Los dos workflows se analizaron como YAML. Los siete archivos originales de dise?o coinciden byte por byte con el ZIP suministrado.

La suite de Spotify usa respuestas simuladas. La verificaci?n puntual separada del proveedor real est? documentada en `spotify_metadata.md`; no forma parte de los tests. Las pruebas LAN usan loopback y relojes simulados, sin dispositivos. Bluetooth, c?mara, redes entre dispositivos f?sicos, calidad de sincron?a y controles de ventana requieren comprobaci?n manual adicional. No se ha ejecutado un workflow remoto de estos cambios.
