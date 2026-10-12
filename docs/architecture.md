# Organización de Aurora

Aurora usa Flutter y Dart para Windows y Android. Esta primera etapa mueve solo
las recomendaciones y la persistencia a sus módulos; conserva las funciones,
la API del controlador y el esquema SQLite versión 1.

```text
lib/
  main.dart                    # Arranque, dependencias y tema
  app_controller.dart          # Coordinación, estado y cola
  core/                        # Track, playlists y contratos de audio/fuentes
  audio/                       # SoLoud, controles del sistema y cálculo de audio
  sources/                     # Extracción con yt-dlp y transmisión progresiva
  dj/
    recommendations.dart       # Puntuación local, razones y claves de identidad
  library/
    library_database.dart      # Biblioteca, favoritos, playlists e historial SQLite
  import/
    spotify_import.dart        # Lectura de exportaciones de Spotify existentes
  lyrics/                      # Consulta y caché de letras
  ui/                          # Pantallas, reproductor, cola y diálogos
test/                          # Pruebas unitarias y de widgets
integration_test/              # Pruebas con aplicación y audio nativos
scripts/                       # Preparación, empaquetado y verificaciones nativas
```

El flujo sigue siendo interfaz → controlador → contratos/proveedores y base de
datos. El DJ depende de los modelos compartidos, y la persistencia también;
ninguno depende de widgets. Los proveedores de audio no deben consultar el DJ.

La siguiente etapa incorporará metadatos en `lib/metadata/spotify/`, separados
de `sources/`: Spotify describirá canciones, artistas, álbumes y playlists;
yt-dlp y los archivos locales seguirán aportando el audio. Los modelos comunes
permanecerán en `core/` cuando los necesiten varios módulos.

`aurora_shell.dart` reúne navegación y muchas pantallas, y `app_controller.dart`
coordina numerosas funciones. La mejora de interfaz debe extraer los componentes
que modifique a `ui/`, con datos y acciones recibidos del controlador, sin mover
pantallas ajenas al trabajo ni introducir lógica del recomendador en widgets.
La ampliación del DJ se hará en `dj/`, manteniendo su puntuación comprobable sin
Flutter. No se agregan repositorios, fábricas ni capas de servicios duplicadas.

El historial actual registra la última reproducción de cada canción (hasta 100
identificadores), no contadores, omisiones ni reproducciones completadas. Estas
señales no se deben inferir como datos existentes. No hace falta una migración
para separar módulos ni para usar favoritos, playlists y recencia.
