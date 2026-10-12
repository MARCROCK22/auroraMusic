# Del diseño original a Flutter

La dirección visual es **Atelier Sonoro**, suministrada en el directorio local
`diseñoidea/`. La implementación traduce composición, tipografía, colores,
fundas de discos, navegación y controles a Flutter para Windows y Android;
conserva el audio, la biblioteca y los proveedores existentes.

## Referencias originales preservadas

La raíz de las pantallas originales es:

```text
diseñoidea/stitch_aurora_music_player_ui/stitch_aurora_music_player_ui/
```

| Pantalla | HTML original | Captura original |
| --- | --- | --- |
| Inicio | `inicio_aurora_music_player/code.html` | `inicio_aurora_music_player/screen.png` |
| Descargas | `descargas_locales_aurora/code.html` | `descargas_locales_aurora/screen.png` |
| Letras | `letras_din_micas_aurora/code.html` | `letras_din_micas_aurora/screen.png` |

La guía es `atelier_sonoro/DESIGN.md`, dentro de esa misma raíz. El archivo fuente
es `diseñoidea/stitch_aurora_music_player_ui.zip`. Estos siete archivos extraídos
se compararon byte a byte con el ZIP y coinciden. No se modificaron ni se
reemplazaron. El material local del usuario permanece en el workspace original;
no forma parte del arranque de Aurora ni de un navegador embebido.

SHA-256 del ZIP comprobado:
`d6f160648c1840eaf330465b037ee0f7849688ea92f7275521e31011909618d6`.

## Recursos y tipografía

`assets/design_idea/` conserva **20 imágenes descargadas de las URLs de los HTML
originales**: diez de Inicio, ocho de Descargas y dos de Letras. El inventario
[sources.json](../assets/design_idea/sources.json) registra URL original,
descripción, pantalla, archivo, tamaño y SHA-256. Se verificaron los veinte
archivos contra ese inventario y la presencia de sus URLs en los originales.
Las portadas de las canciones y los datos de biblioteca siguen procediendo del
estado real del reproductor; los recursos de referencia no crean un catálogo,
estadísticas ni sesiones de demostración en producción.

Newsreader normal e italic y Plus Jakarta Sans están empaquetadas localmente,
con sus avisos [OFL de Newsreader](../assets/fonts/newsreader/OFL.txt) y
[OFL de Plus Jakarta Sans](../assets/fonts/plus_jakarta_sans/OFL.txt).
Material Symbols Outlined usa un subconjunto local de **78 glifos**, mapeado en
[codepoints.json](../assets/fonts/material_symbols_outlined/codepoints.json),
con la [licencia Apache 2.0](../assets/fonts/material_symbols_outlined/LICENSE).
`StudioSymbols` selecciona estos glifos; no hay una petición de Google Fonts al
mostrar las pantallas. Se mantienen los controles y estados de Flutter.

## Comportamiento implementado

| Superficie | Implementación y datos reales |
| --- | --- |
| Cabecera y navegación | Ventana nativa Windows, destinos de biblioteca/vinilo/letras, acceso a Jam y badge de sesión con su estado real. Barra lateral en escritorio; navegación y más vistas en móvil. |
| Inicio | Cabecera editorial, funda principal y rotación reciente; recomendaciones, playlists y agrupaciones por artista/álbum de la biblioteca. Las filas horizontales admiten tacto, trackpad, Shift + rueda y botones. |
| Atajos del Inicio | Jazz y Acústica Nórdica abren búsquedas reales; las opciones de ánimo o simulación aún no implementadas muestran un aviso explícito. |
| Transporte persistente | Reproducción/pausa, anterior/siguiente, aleatorio, repetición, favoritos, volumen y posición utilizan el audio real. Durante el overlay Jam se muestra su estado propio. |
| Panel de sesión | QR solo cuando existe una Jam anfitriona, cantidad real de participantes, autoría y próxima cola. Sin sesión ofrece crear/unirse; el ecualizador usa bandas y ganancias reales. |
| Descargas | Carpeta y controles disponibles por plataforma, trabajos/progreso, cancelación y reintento; filtro, importación, reproducción y eliminación confirmada de archivos conocidos. Tabla de escritorio y tarjetas móviles. Tamaño por `File.stat` y formato por extensión. |
| Letras | Consulta/caché LRCLIB e importación LRC/TXT, carga/error/ausencia; seguimiento de versos, buscar posición al tocar una línea, vista tradicional, tipografía y offset manual de 0,5 s. Cambiar de pista restablece el offset. |
| DJ | Izquierda u Omitir descarta la tarjeta de esta sesión. Derecha o Añadir y seguir guarda el favorito y encola sin duplicados. La razón y los filtros corresponden a las señales locales; puede buscar novedades opcionales con el proveedor existente. |
| Jam | Cola autoritativa LAN, permisos por persona, reconexión y audio sincronizado opcional con fuentes propias. Continúa compartiendo la cola cuando una pista no está disponible en un dispositivo. |

La navegación mantiene Jam montada después de la primera visita, para que abrir
Inicio o DJ no cierre la sesión. Su controlador sigue siendo creado bajo demanda.
Los carruseles no sustituyen el desplazamiento vertical y los gestos del DJ tienen
botones equivalentes para ratón y teclado. Las pantallas contemplan anchos móviles,
texto ampliado, errores, carga y datos vacíos.

## Conceptos que siguen pendientes

El texto editorial del original sobre 432 Hz, cinta Studer, válvulas y calibración
no certifica DSP, latencia DAC ni fidelidad del audio. Se conserva como referencia
visual junto a indicaciones de simulación pendiente. El ecualizador de ocho bandas
y el visualizador FFT existentes sí funcionan; no son una emulación analógica ni
una forma de onda preanalizada del archivo completo.

Exportación a USB, auditoría CRC/Hash de archivos musicales, escritura directa,
respaldo automático, traducción de letras y notas de producción no están
implementados. Los controles conceptuales muestran Pendiente o un aviso, sin
simular éxito. Bitrate, espacio libre y fidelidad tampoco se infieren de la
extensión del archivo. La validación de hashes de herramientas de compilación es
una función distinta de esa auditoría musical pendiente.

## Usar Jam y sus límites

Abre Jam, elige Crear Jam, selecciona una dirección privada y pulsa Iniciar sesión
local. El otro dispositivo puede escanear el QR desde Aurora. Android abre cámara
solo al activar Escanear QR; Windows importa una imagen o recibe la invitación
copiada. No se pide cámara ni se abre un servidor al iniciar la app.

Cola compartida permite a todos agregar; el anfitrión decide quién omite,
reordena o quita. Reproducción sincronizada mantiene play/pausa y posición bajo
su autoridad; cada invitado activa audio en su dispositivo. La posición inicial
se estima con el reloj de la sesión y los ajustes posteriores se limitan a 500 ms
cada cinco segundos cuando el desfase supera 750 ms. Diferencias de versión,
carga y proveedor impiden prometer sincronía exacta.

Jam admite IPv4 RFC1918, hasta 16 identidades y 200 canciones, con diez solicitudes
por participante cada cinco segundos. El acceso temporal es aleatorio de 256 bits
y vence en cuatro horas como máximo; cerrar invalida los accesos. No se envían
rutas, archivos, URLs extraídas ni credenciales. La conexión LAN y el QR no están
cifrados: utiliza una red de confianza. Firewall y aislamiento del router pueden
impedir la conexión. Cámara, red entre dispositivos físicos y sincronía audible
requieren comprobaciones de hardware. Más detalle en [Jam](jam.md).

## Verificación y lectura adicional

Esta documentación identifica los archivos y contratos integrados; no declara
aprobadas compilaciones finales todavía en curso. El inventario de imágenes y los
originales se verificaron localmente. Las pruebas funcionales, de widgets y de
protocolo se describen en [VALIDATION.md](VALIDATION.md), [paneles](design_idea_panels.md),
[DJ](dj.md), [metadatos](spotify_metadata.md) y [Jam](jam.md).
Los secretos y la firma se documentan únicamente en [CI y firma](ci_signing.md);
no se reproducen sus valores aquí.
