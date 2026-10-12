# Entrega integrada de Aurora

Los cambios se revisaron e integraron en `main` conservando los archivos originales de `diseñoidea/`. No se modificó el esquema SQLite ni se reemplazó la identidad de firma.

## Trabajo separado

| Responsable | Rama | Resultado |
| --- | --- | --- |
| architecture | refactor/aurora-architecture | Separación de biblioteca y recomendador; primera etapa compilada antes de las funciones |
| spotify | feat/spotify-metadata | Proveedor anónimo de metadatos y pruebas simuladas |
| dj | feat/dj-recommendations | Puntuación explicable, filtros, identidad de canciones y cola |
| ui | feat/music-ui | Componentes de biblioteca, búsqueda y estados |
| architecture | ci/android-signing | Workflows y restauración segura de la firma existente |
| dj | feat/dj-discovery-ui | Navegación DJ, tarjetas y gestos |
| ui | feat/home-carousels | Filas horizontales con datos reales |
| spotify | feat/lan-jam | Comunicación LAN, cola compartida, QR y sincronización |
| coordinador | feat/jam-playback-isolation | Aislamiento y restauración del reproductor personal |
| coordinador | feat/design-idea-flutter | Recursos originales, tema, Inicio, navegación y controles nativos |
| ui | feat/design-idea-panels | Descargas y Letras fieles a la referencia |
| dj | test/design-idea-ui | Pruebas y capturas de la interfaz integrada |
| spotify | docs/aurora-delivery | Inventario visual y arquitectura final |

Cada tarea tuvo un worktree y una rama propios. Se revisaron los cambios antes de integrarlos mediante merges o cherry-picks identificables. Los worktrees anteriores ajenos a este trabajo se conservaron. La revisión adicional `test/jam-and-dj` no produjo cambios: ese agente agotó su disponibilidad; el coordinador realizó la revisión y ejecutó las 41 pruebas focalizadas de Jam y DJ.

## Funciones

**Spotify** permite buscar canciones, artistas, álbumes y playlists, consultar detalles y paginar. Usa el mecanismo del plugin Nuclear: autenticación anónima del reproductor web, TOTP y consultas Pathfinder. Tiene caché, concurrencia limitada, deduplicación, renovación y reintento controlado. Los tokens no se muestran. Para reproducir una canción se selecciona una coincidencia del proveedor de audio existente; Spotify solo aporta metadatos. Los endpoints privados pueden cambiar. Licencia y atribución AGPL-3.0 del código de referencia están en `third_party/nuclear_spotify/`. Detalles en [spotify_metadata.md](spotify_metadata.md).

**DJ** aparece inmediatamente debajo de Buscar. Deslizar a la izquierda omite y avanza; a la derecha guarda interés mediante favoritos, agrega a la cola y avanza. También hay botones, bloqueo contra acciones repetidas y movimiento reducido. Puntúa artistas y géneros presentes en favoritos, pertenencia a playlists y recencia del historial; penaliza repeticiones y limita la diversidad de artistas. No inventa frecuencia, omisiones ni finalizaciones, porque no existen esos registros. Los filtros incluyen/excluyen artistas, canciones y géneros. Detalles en [dj.md](dj.md) y [dj_discovery.md](dj_discovery.md).

**Inicio** mantiene filas horizontales reales de recientes, recomendaciones, biblioteca y colecciones disponibles. Funcionan con tacto, arrastre, trackpad, Shift+rueda, flechas y teclado; la rueda vertical sigue moviendo la página. No se crean colecciones vacías ni canciones ficticias. Detalles en [home_carousels.md](home_carousels.md).

**Jam** se abre desde la navegación o el panel de sesión. El anfitrión elige su dirección LAN y crea la sala; los invitados escanean el QR desde Aurora, importan una imagen QR o pegan la invitación. Windows permite imagen/invitación; la cámara Android se solicita solo al escanear. La cola compartida admite contribuciones, nombres, permisos de quitar/reordenar/omitir y límites contra duplicados y spam. El modo sincronizado requiere activación de escucha en cada invitado: cada dispositivo resuelve su propio audio. El anfitrión es autoritativo; los ajustes tienen tolerancia de 750 ms y pasos de hasta 500 ms cada 5 segundos. No se transmiten URLs extraídas, cookies, credenciales ni archivos de audio. La cola funciona aunque un tema no pueda reproducirse en un dispositivo. QR temporal, token aleatorio, expiración, cierre, reconexión y mensajes validados. La sincronía es aproximada y depende de las fuentes. Detalles en [jam.md](jam.md).

**Interfaz de referencia**: Inicio, Descargas y Letras se construyeron con widgets nativos, recursos originales empaquetados y las fuentes Newsreader/Plus Jakarta Sans/Material Symbols. No se usan WebViews ni capturas como fondos. Los datos de canciones, archivos, cola y reproducción proceden de Aurora; las capturas automatizadas usan fixtures sin red. Cinta/válvulas/432 Hz, medición DAC, CRC, USB, respaldo y traducción indican que están pendientes. Inventario y límites en [design_idea_implementation.md](design_idea_implementation.md).

## Firma

Los cuatro Repository Secrets Android se actualizaron con GitHub CLI autenticado el 12 de octubre de 2026 en `kaz-py/auroraMusic`, usando la keystore existente y validando su clave localmente. No faltan secretos Android: `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Se administran en Settings → Secrets and variables → Actions. El workflow valida presencia, restaura el archivo con ACL protegida en el runner y lo elimina siempre. Windows conserva ejecutables sin firma Authenticode. Ver [ci_signing.md](ci_signing.md).

## Verificación

El análisis integrado no presenta problemas. Las compilaciones Windows release, Android ARM64 debug y Android ARM64 release se ejecutaron; el APK release supera `apksigner verify`. Los scripts de firma pasan los casos de secretos ausentes, Base64 inválido, ACL, restauración y limpieza. Los dos workflows se analizaron como YAML. Los siete archivos originales de diseño coinciden byte por byte con el ZIP suministrado.

La suite integrada completa aprueba **269 pruebas**. La suite de Spotify usa respuestas simuladas. La verificación puntual separada del proveedor real está documentada en `spotify_metadata.md`; no forma parte de los tests. Las pruebas LAN usan loopback y relojes simulados, sin dispositivos. Bluetooth, cámara, redes entre dispositivos físicos, calidad de sincronía y controles de ventana requieren comprobación manual adicional. Los resultados locales no equivalen a una ejecuci\u00f3n remota de Actions; consulta su estado en GitHub y [VALIDATION.md](VALIDATION.md).
