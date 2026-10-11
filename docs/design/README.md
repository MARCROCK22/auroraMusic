# Diseño de Aurora

La referencia aprobada por el usuario el 11 de octubre de 2026 es el proyecto
[Aurora Music Player UI en Stitch](https://stitch.withgoogle.com/projects/9790980624970578261).
Las capturas `reference-desktop.png` y `reference-desktop-mobile.png` conservan
las pantallas que eligió como dirección definitiva.

## Dirección visual

- Fondo carbón cálido y superficies marrón tinta; texto marfil.
- Acento naranja inicial, adaptable a la portada de la canción activa.
- Newsreader para títulos y Plus Jakarta Sans para controles y metadatos.
- Navegación compacta, portadas protagonistas y controles persistentes.
- Biblioteca en cuadrícula; búsqueda en filas; cola y letras con espacio propio.
- Ajustes en dos columnas en escritorio, apilados en pantallas pequeñas.
- Descargas locales visibles, con ubicación y acciones para cambiar o abrir carpeta.
- En Android, cuatro destinos principales y un reproductor expandible.

## Comprobación del centrado

Las portadas geométricas de las capturas de prueba son ilustraciones originales:
su círculo ocupa el centro del cuadrado y el rótulo queda debajo. No se modifican
las portadas reales de la biblioteca. El disco, sus surcos, la etiqueta y el
agujero del vinilo comparten centro; una prueba comprueba ambas coordenadas con
tolerancia de un píxel lógico en escritorio y móvil.

## Trabajo supervisado

Preferencia explícita del usuario: usar subagentes Codex con el modelo Luna para
el diseño. El coordinador asigna archivos sin solapamientos, revisa los cambios,
ejecuta las pruebas conjuntas y verifica las compilaciones. No modificar
`AGENTS.md` para registrar esta preferencia.

## Fidelidad funcional

Las imágenes de Stitch contienen conceptos adicionales. No presentar códigos QR,
estadísticas, etiquetas o datos técnicos simulados como funciones disponibles.
Los controles visibles deben utilizar el estado real del reproductor. Las letras
dependen de disponibilidad en LRCLIB o de un archivo local importado. Un
visualizador FFT en tiempo real no equivale a una forma de onda analizada de la
canción completa. La selección de carpeta de descargas se implementa en Windows;
Android conserva el almacenamiento privado de la aplicación.
