# Descargas y letras del Atelier Sonoro

Se reconstruyeron los paneles originales `descargas_locales_aurora` y
`letras_din_micas_aurora` con widgets Flutter. Se conservan jerarquía, composición
asimétrica, Newsreader, paneles oscuros, sombras sin desenfoque y acentos cálidos.
Los originales permanecen intactos. El shell y sus recursos son compartidos.

- `lib/ui/studio/downloads_studio_page.dart`: depósito local, carpeta, conteos,
  progreso real, pestañas, filtro, importación, reproducción, cancelación,
  reintento y eliminación confirmada. En escritorio muestra tabla; en móvil,
  tarjetas y controles que pueden envolver líneas con texto ampliado.
- `lib/library/local_file_metadata.dart`: consulta únicamente los archivos
  conocidos, omite directorios e inaccesibles y no registra sus rutas. La pantalla
  memoriza la consulta mientras IDs, estados y rutas no cambien.
- `lib/ui/lyrics_panel.dart`: conserva búsqueda, caché, LRC/TXT, control de
  reproducción, descarte de respuestas antiguas y desplazamiento sincronizado.
  Añade vista tradicional, tipografías y offset manual en pasos de 0.5 segundos.
  El offset se reinicia al cambiar de pista; adelantar letras también ajusta el
  seek al tocar un verso, sin cambiar el estado de reproducción.

El formato de descarga procede de la extensión, y el tamaño de `File.stat`;
no se infieren bitrate, fidelidad, espacio libre ni certificaciones. La selección
de nuevos archivos usa el importador existente, sin simular una exploración
automática. USB, CRC, escritura directa, respaldos y traducción se muestran como
pendientes. Los modelos actuales no proporcionan notas de producción.

Validación: `flutter analyze --no-pub` sin incidencias. Los 20 tests existentes de
letras/reproductor y cuatro pruebas nuevas de archivos, offset/modos, descargas y capturas
a 320 px con texto 200% pasan. Las letras usan un servicio simulado sin red.
No se verificó reproducción física ni selectores nativos en dispositivos.
Capturas con Newsreader, Plus Jakarta Sans y símbolos originales en
`build/ui-review/studio-{downloads,lyrics}-{ancho}.png`, con fixtures offline.
Descargas se revisa a 1286×1913, letras a 1600×1400 y ambas a 320×800 con texto 200%.
