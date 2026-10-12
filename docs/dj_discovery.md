# DJ de descubrimiento

La vista **DJ** aparece inmediatamente debajo de **Buscar**. Conserva los índices
anteriores de navegación: DJ usa 8 y Jam usa 9. Android muestra cinco destinos:
Inicio, Buscar, DJ, Biblioteca y Descargas. Jam está también en **Más vistas**.

`lib/ui/dj_discovery_page.dart` muestra una tarjeta con datos disponibles de una
recomendación real: portada o el marcador existente, título, artista, álbum,
géneros, duración y explicación del recomendador. No inventa álbumes ni géneros.
`lib/dj/discovery_controller.dart` conserva elecciones y concurrencia separadas
del widget; reutiliza las recomendaciones y novedades del controlador de Aurora.

- Deslizar hacia la izquierda u **Omitir** avanza la tarjeta. Es una elección de
  esta sesión de descubrimiento, no un salto de reproducción registrado.
- Deslizar hacia la derecha o **Añadir y seguir** guarda un favorito, si todavía
  no lo era, y añade la canción a la cola mediante la protección de duplicados
  existente. Conserva la reproducción actual; nunca reproduce automáticamente.
- Solo se consideran canciones reproducibles, nunca metadatos Spotify pendientes
  de una coincidencia. Los filtros existentes se aplican también a esta vista.
- Una elección pendiente bloquea acciones sobre esa tarjeta. Una acción tardía
  no decide sobre la siguiente. En un fallo de persistencia se presenta un error
  y se conserva la tarjeta para reintentar; no se afirma que haya sido guardada.

Los gestos necesitan al menos 80 píxeles horizontales y superar 1,5 veces el
desplazamiento vertical máximo. Los movimientos pequeños, verticales y diagonales
dominados por el eje vertical no deciden. La observación de punteros no captura
la interacción de desplazamiento vertical; hay botones accesibles alternativos.
La opción de movimiento reducido elimina el desplazamiento decorativo de portada.

Las identidades visitadas (ID, URL canónica y URI Spotify) viven solo mientras
esta vista permanece abierta. Actualizar o descubrir novedades no vuelve a
mostrar las que ya se decidieron. Cerrar y volver a abrir inicia otra sesión.
No se generan estadísticas ficticias de escucha, frecuencia ni finalizaciones.
Los favoritos reales guardados sí actualizan el recomendador existente.

No se hacen búsquedas de red al abrir la vista: **Buscar novedades** es explícito
y usa el proveedor existente y sus límites. Si no quedan resultados, la vista
ofrece búsqueda y los controles de filtros, sin secciones de relleno.

La composición de Inicio se delega a `HomeMusicPage` y la vista Jam a `JamPage`.
Durante reproducción controlada desde Jam, el shell muestra ese estado con
**Abrir Jam** y oculta el reproductor personal y su panel lateral para no mostrar
la posición compartida como si perteneciera a una canción personal.

Pruebas: gestos horizontales, pequeños y verticales, botones, favoritos existentes,
duplicados, elecciones concurrentes, ausencia de datos, filtros, movimiento
reducido y texto al 200% en 320 px. Capturas locales de la tarjeta:
`build/ui-review/dj_discovery/card-960.png` y `card-390.png` (datos simulados de prueba).
