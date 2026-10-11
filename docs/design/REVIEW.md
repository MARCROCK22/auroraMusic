# Revisión visual y funcional de Aurora

Revisión de solo lectura del código actual (`lib/ui/aurora_shell.dart`, `vinyl_player.dart`, `queue_panel.dart`, `lyrics_panel.dart` y `main.dart`) frente a `reference-desktop.png`, `reference-desktop-mobile.png` y los PNG individuales exportados en `docs/design/` (marcados por el explorador el 11/10/2026). Las referencias aprobadas definen el objetivo; los PNG individuales son pantallas de diseño, no capturas de la app ejecutándose. No usé `build/screenshots/aurora-redesign*.png` como evidencia de la vista nativa actual, porque su versión puede ser anterior.

## Cinco hallazgos prioritarios

1. **La vista de vinilo queda fuera de la navegación móvil.** En anchos menores de 600 px, `aurora_shell.dart:174-189` crea una `NavigationBar` con destinos 0–3 únicamente. La entrada Vinyl está en el índice 4 (`:15-34`), y el mini reproductor compacto no ofrece un acceso a Vinyl (`:1591-1609`); el reproductor expandido sí da acceso a letras y cola (`:1785-1802`), pero no al modo vinilo. La pantalla `inicio_aurora_android.png` muestra la app en móvil y el modo vinilo está aprobado como destino del producto en escritorio. **Cambio mínimo:** exponer Vinyl desde un menú de más destinos o acción del reproductor expandido; conservar los cuatro destinos principales de la barra y no simular elementos exclusivos de escritorio.

2. **Letras tapa la navegación de escritorio en vez de ocupar el espacio de contenido.** El elemento lateral abre `_showLyrics` sin cambiar `_section` (`aurora_shell.dart:263-280`); `_showLyrics` construye `Dialog.fullscreen` (`:1979-1983`). La referencia de letras mantiene el rail y el reproductor inferior, mostrando la portada y el texto sincronizado en el área central. **Cambio mínimo:** presentar `LyricsPanel` como destino/página dentro del shell en escritorio, conservando su presentación compacta en móvil; mantener los estados actuales de no disponible, error e importación.

3. **No hay acción para quitar una pista individual de la cola.** Las filas de `QueuePanel` solo muestran duración y el icono de arrastre (`queue_panel.dart:218-240`), aunque el controlador ya implementa `removeFromQueue` (`app_controller.dart:515-534`). En una cola larga, quitar una pista requiere navegación/reordenamiento indirectos. **Cambio mínimo:** añadir una acción accesible «Quitar de la cola» por fila, conectada al método existente, y reservar un área táctil visible; mantener el gesto de reordenar como acción adicional.

4. **El modo Vinilo omite el contexto de álbum que da sentido al plato de la referencia.** La vista actual centra un disco genérico con la portada recortada en su etiqueta (`vinyl_player.dart:105-175`) y luego muestra título, artista y seek/controles (`:177-260`). La referencia `modo_vinilo_aurora.png` organiza edición/álbum y lista de caras a la izquierda, plato al centro y panel de letras/contexto a la derecha. **Cambio mínimo:** conservar el disco y los controles reales, pero dar prioridad en escritorio a metadatos y pistas ya disponibles en la biblioteca; no añadir datos de prensado, BPM o letra inventados.

5. **El panel de reproducción actual pierde la carátula y controles secundarios en escritorio estrecho.** Con 900–1199 px el shell reserva un rail de iconos de 76 px y no muestra el panel “Ahora suena” (umbral de 1200 px en `aurora_shell.dart:143-166`); el mini reproductor en ese rango omite favorito, cola, ecualizador y volumen, que solo aparecen cuando `wide` es verdadero (`:1581-1650`). Esto deja los controles visibles menos parecidos a la barra persistente de `reference-desktop.png` precisamente en una ventana común de laptop. **Cambio mínimo:** priorizar carátula y acciones esenciales en un panel adaptable de una columna o hacer crecer el panel lateral antes del breakpoint de 1200 px; permitir que los controles secundarios pasen a un menú si no caben.

## Límites de la evidencia

No ejecuté pruebas, builds ni la aplicación, según el encargo. Los hallazgos 1–3 se basan en rutas y métodos visibles en el código; los 4–5 son diferencias concretas entre la estructura actual y la composición aprobada. Las referencias de Stitch muestran algunos conceptos de presentación que no deben copiarse como datos o funciones simulados (por ejemplo, estados de red compartida o especificaciones de vinilo); los cambios sugeridos reutilizan estado real y mantienen los estados vacíos y de error existentes.

## Comprobación posterior del coordinador

Se incorporaron el menú móvil **Más vistas**, letras dentro del shell, cierre a
Inicio y eliminación de una aparición desde la cola. Vinilo muestra la pista
actual y las próximas canciones reales. Las 12 pruebas de interfaz verifican
navegación móvil, texto al 200 %, escritorio de 600 px de alto y recuperación de
estados; el coordinador también revisó capturas nativas de Windows.

El hallazgo 5 describía incorrectamente el umbral: `wide` comienza a 900 px y el
panel adicional a 1200 px. Los controles inferiores de escritorio se muestran
desde 900 px. Las referencias de líneas del informe corresponden a su revisión
original y pueden haber cambiado.
