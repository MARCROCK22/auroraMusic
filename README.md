# Aurora

Reproductor de música en Flutter y Dart para **Windows x64 y Android 7+**. Interfaz en español, biblioteca local y fuentes públicas de YouTube mediante yt-dlp ejecutado en el dispositivo.

## Funciones

- Inicio, búsqueda, importación de enlaces/listas de YouTube y archivos locales.
- Favoritos, playlists editables, historial y cola reordenable; aleatorio, repetición, volumen, avance y temporizador.
- Importación gratuita de playlists de Spotify desde JSON/CSV local, con vista previa y elección explícita de la versión en YouTube; sin configurar claves de API.
- Búsqueda de canciones, artistas, álbumes y playlists de Spotify mediante el proveedor de metadatos adaptado de Nuclear, sin cuenta personal ni Premium.
- Descargas locales MP3 con progreso, cancelación, reintento y eliminación; carpeta de destino configurable en Windows y biblioteca disponible sin conexión.
- Interfaz Atelier Sonoro reconstruida en Flutter a partir de los originales de `diseñoidea/`: Newsreader normal e italic, Plus Jakarta Sans, símbolos locales y navegación adaptable.
- Biblioteca en cuadrícula, cola con vista propia y ajustes por secciones. **Modo Vinilo** gira durante la reproducción y permite desplazar la posición arrastrando el disco.
- Botón **Letras**: búsqueda exacta en LRCLIB, texto sincronizado o tradicional, caché privada e importación de archivos LRC/TXT.
- Letras interactivas: toca un verso sincronizado para avanzar o retroceder, ajusta el volumen y vuelve al reproductor con **Volver**. Buscar una posición conserva tu decisión de reproducir o pausar.
- Inicio con carruseles horizontales de datos reales; DJ de descubrimiento con gestos: izquierda omite, derecha guarda el favorito y encola.
- **Para ti** recomienda según favoritos, listas y escuchas recientes. **DJ personal**, sin voz, continúa la cola con esas preferencias; las novedades de YouTube son opcionales y se consultan con límites visibles.
- **Jam**: cola compartida en red local, QR, permisos del anfitrión y reproducción sincronizada opcional con fuentes de audio propias.
- Colores extraídos de la portada, ambiente reactivo a la energía y visualizador FFT del audio real.
- Ecualizador DSP de ocho bandas, presets y reducción automática de ganancia para los refuerzos.
- Controles multimedia del sistema, servicio de audio Android, pausa por desconexión e interrupciones de audio.
- SQLite local; restaura cola y posición **en pausa**. Temas claro/oscuro/sistema y movimiento reducido.
- Paletas Automático, Morado, Terracota, Ámbar y Verde bosque para toda la interfaz.

Spotify aporta descripciones y portadas; el audio proviene de archivos locales y
YouTube. El DJ usa señales locales y filtros persistentes por artista, canción y
género conocido.

### Explorar Spotify y personalizar el DJ

Abre **Buscar → Metadatos · Spotify**, escribe el nombre y elige canciones,
artistas, álbumes o playlists. Las colecciones muestran sus canciones y permiten
cargar más resultados. **Añadir a la cola** abre la búsqueda de coincidencias de
YouTube: elige una fuente y confirma **Añadir a la cola** o **Reproducir**.
La cola elimina duplicados por canción, URL canónica y referencia de Spotify.

En **DJ**, desliza a la izquierda para omitir una tarjeta y a la derecha para guardar el favorito y añadirla a la cola; también hay botones equivalentes. Estas omisiones son elecciones de la sesión, no un historial de saltos de reproducción.

En **Inicio → Para ti → Personalizar el DJ**, selecciona artistas, canciones o
géneros de tu biblioteca. Las dimensiones se combinan; **Quitar filtros** las
restablece. Los géneros solo se ofrecen cuando existen en los datos. Las
recomendaciones explican sus señales y se actualizan con favoritos, playlists e
historial reciente. Los filtros afectan incorporaciones nuevas del DJ.

El método de Spotify depende de interfaces privadas que pueden cambiar. La
adaptación conserva la licencia AGPL-3.0 y sus avisos. Consulta
[metadatos](docs/spotify_metadata.md), [DJ](docs/dj.md) e
[interfaz](docs/music_ui.md) para detalles y límites.

### Compartir una Jam local

Abre **Jam → Crear Jam**, elige la dirección privada de tu Wi-Fi/Ethernet y pulsa
**Iniciar sesión local**. Aurora muestra el QR; las demás personas lo leen desde
Jam. Android permite cámara bajo demanda. Windows permite importar una imagen QR
o pegar la invitación copiada por el anfitrión.

**Cola compartida** permite agregar a todos y muestra quién eligió cada canción;
el anfitrión concede permisos para omitir, reordenar y quitar. En **Reproducción
sincronizada**, controla canción, pausa y posición; los invitados activan audio
local y cada dispositivo utiliza su propia biblioteca/proveedores. Una canción
no disponible genera un aviso sin cerrar la cola. La sincronía es aproximada.

La sesión y sus accesos son temporales, con hasta 16 identidades y 200 canciones.
No se transfieren archivos, rutas ni credenciales; la conexión LAN no está cifrada
ni se publica en Internet. Usa una red de confianza. **Reconectar** recupera la
identidad durante la sesión; **Salir/Cerrar Jam** invalida el acceso correspondiente.
La cola personal permanece separada. Consulta [Jam](docs/jam.md) para límites,
permisos de plataforma y comprobaciones físicas pendientes.

### Diseño y funciones pendientes

La [implementación del diseño original](docs/design_idea_implementation.md)
identifica los tres HTML, tres PNG, DESIGN.md y ZIP preservados, los veinte recursos
con sus URLs/hashes y las fuentes incluidas. Inicio, transporte, descargas y letras
usan datos y acciones reales. La simulación de válvulas/cinta, exportación USB,
auditoría musical CRC/Hash, respaldo y traducción siguen pendientes y se señalan
como tales en la interfaz. Las etiquetas editoriales no certifican fidelidad,
latencia ni DSP analógico.

### Encontrar descargas y letras

Abre **Descargas locales** en la navegación o desde Inicio. La ruta aparece en la página: **Cambiar carpeta** selecciona un destino para futuras descargas y **Abrir carpeta** lo abre en Explorer. Las descargas existentes conservan su ubicación; no se trasladan ni sobrescriben archivos. Espera a que terminen los trabajos activos antes de cambiarla. **Biblioteca → Archivos locales** reúne los archivos importados y descargados.

En Android, las descargas permanecen en el almacenamiento privado de Aurora; la selección de una carpeta externa aún no está implementada.

El botón **Letras** está en el reproductor inferior y en la cabecera del reproductor completo. Al abrirlo, se envían título y artista a LRCLIB si no existe una copia local. Las letras sincronizadas siguen la posición de reproducción. No todas las pistas tienen coincidencia: puedes importar tu propio `.lrc` o `.txt` (máximo 1 MiB), cuyo original permanece intacto. Las letras guardadas funcionan sin conexión.

En escritorio, la entrada **Letras** mantiene la navegación y los controles inferiores; el botón del reproductor abre la vista completa. En móvil, **Más vistas** abre vinilo, cola o letras, conservando los cuatro destinos principales. En la cola, el menú de cada pista permite quitar esa aparición sin borrar el archivo. Las referencias y la preferencia de trabajar con subagentes Luna están en [docs/design/README.md](docs/design/README.md).

## Ejecutar desde el código

Las ramas de desarrollo y pruebas usan `aurora/<cambio-o-prueba>` (por ejemplo, `aurora/corregir-cache`). Cada subagente trabaja en su propia rama y checkout; la integración y las pruebas preceden a la publicación en `main`.

Requisitos usados: Flutter 3.38.8 / Dart 3.10.7. Para Windows: Visual Studio con desarrollo de escritorio C++; para Android: SDK Android, Java 17+ y dispositivo/emulador de 64 bits. Usa el Dart incluido en Flutter.

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run -d windows --no-pub
# O selecciona un dispositivo Android:
flutter devices
flutter run -d <device-id> --no-pub
```

Si Windows impide crear los enlaces de plugins, ejecuta `./scripts/prepare_windows_plugins.ps1` después de `flutter pub get`. El script crea junctions dentro del proyecto, sin cambiar opciones del sistema.

### Herramientas Windows

`flutter run -d windows` y `flutter build windows` preparan automáticamente las herramientas durante la compilación: descargan las versiones fijadas si faltan, verifican sus hashes y las copian a `tools/` junto al ejecutable. Aurora las detecta sin configurar carpetas. La primera compilación necesita acceso a Internet; las siguientes reutilizan las herramientas verificadas.

```powershell
./scripts/setup_tools.ps1
```

Este comando permite prepararlas por separado. Descarga versiones oficiales verificadas de yt-dlp, Deno, FFmpeg y ffprobe en `tools/windows/`, junto a hashes, versiones y licencias. `scripts/windows_tools.lock.json` fija las versiones predeterminadas. **Ajustes → Herramientas** permite un diagnóstico o una carpeta personalizada. No se ejecutan herramientas encontradas arbitrariamente en `PATH`.

Android incorpora Python, JavaScript, yt-dlp y FFmpeg mediante `youtubedl-android` 0.18.1; no necesita instalar Python. Las primeras operaciones preparan esos componentes localmente.

### Caché de reproducción en Windows y Android

Para reducir cortes de las URLs temporales de YouTube, Aurora descarga primero el audio completo en su carpeta privada y valida su duración con ffprobe. La primera reproducción necesita esperar la descarga; una copia válida puede reutilizarse. La caché se limita a 512 MB y limpia los archivos más antiguos. **Ajustes → Almacenamiento y biblioteca → Limpiar caché** conserva la canción actual y tus descargas locales. Los paquetes para compartir no incluyen esta caché ni tus datos personales.

Android también descarga y valida el archivo completo antes de reproducirlo. En **Ajustes → Almacenamiento y biblioteca**, **Descargar mientras se reproduce (experimental)** permite comenzar con un WebM compatible mientras yt-dlp sigue descargando. Está desactivado por defecto y afecta a las próximas canciones. Otros formatos conservan la descarga completa; buscar una parte todavía no descargada puede requerir esperar. Los archivos incompletos no se publican como copias válidas.

Los reintentos de reproducción son limitados, conservan la canción y posición, y se cancelan al pausar, detener o cambiar de canción. No evitan restricciones de YouTube ni hacen accesibles videos privados o eliminados.

### Importar playlists de Spotify gratis

1. Obtén el JSON de playlists con la [descarga de tus datos de Spotify](https://support.spotify.com/article/understanding-your-data/) o un CSV de canciones. Aurora admite columnas como `Track Name`, `Artist Name(s)`, `Album Name` y `Track URI`; si el CSV no tiene `PlaylistName`, usa el nombre del archivo.
2. Abre **Biblioteca → Importar de Spotify → Elegir archivo**, revisa las listas y pulsa **Importar**. Cancelar la vista previa no cambia la biblioteca.
3. Abre la lista y toca una canción pendiente para elegir su versión de YouTube. **Guardar** la vincula sin reproducir; **Guardar y reproducir** inicia el audio elegido.

Todo el archivo se procesa localmente, sin claves de API ni pagos. Se conservan los nombres, artistas, álbumes, referencias Spotify, orden y repeticiones. No se transfieren audio descargado de Spotify, credenciales ni estadísticas de escucha. El límite por archivo es 20 MB y 20 000 canciones; podcasts y archivos locales de Spotify se omiten con un aviso.

### Cuando YouTube limita solicitudes

Un HTTP 429 o una petición de verificar la sesión proviene de YouTube. Abre YouTube en tu navegador, inicia sesión y completa cualquier verificación que aparezca. Espera antes de repetir búsquedas. Aurora envía la búsqueda con Enter o la flecha, sin consultar mientras escribes ni duplicar una consulta pendiente.

Si necesitas usar tu sesión, exporta **solo las cookies de YouTube** a un archivo `.txt` en formato Netscape siguiendo la [documentación oficial de yt-dlp](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies). En Aurora, abre **Ajustes → Sesión de YouTube → Importar sesión**. La app valida el archivo y guarda una copia en su carpeta privada; puedes reemplazarla o eliminarla desde esa misma sección. El archivo original permanece intacto. La sesión es opcional y no elimina un bloqueo de la dirección IP.

El archivo permite acceder a tu sesión: mantenlo privado y no lo adjuntes a incidencias ni al repositorio. Aurora no lo cifra ni lee automáticamente las credenciales del navegador. Si la sesión caduca, importa un archivo actualizado.

### Compatibilidad Android de 16 KB

La dependencia original contiene cinco bibliotecas WebP con alineación de 4 KB. Antes de distribuir un APK, prepara el parche reproducible:

```powershell
./scripts/rebuild_android_webp.ps1
```

Requiere NDK 28.2.13676358 y CMake 3.22.1 instalados en el SDK. Descarga WebP 1.6.0 desde su origen oficial, comprueba hashes y recompila las bibliotecas con alineación de 16 KB. Conserva nombres, símbolos y avisos de licencia. Gradle verifica el AAR resultante en `tools/android/`; si falta, utiliza el original y emite una advertencia. El parche y los binarios generados no se guardan en Git.

## Compilar y distribuir

```powershell
flutter build windows --release --no-pub
./scripts/package_windows.ps1
flutter build apk --debug --no-pub --target-platform android-arm64
./scripts/verify_android_alignment.ps1
```

El ZIP Windows queda en `dist/`, con herramientas verificadas y avisos de licencia. Extrae **toda** la carpeta y abre `aurora_music.exe`. El empaquetado comprueba que `flutter_windows.dll` sea la del motor release; no compiles debug y release simultáneamente sobre los mismos archivos. Si existe un paquete anterior, el nuevo recibe un nombre con fecha.

El APK de desarrollo queda en `build/app/outputs/flutter-apk/app-debug.apk`. Se instala directamente en teléfonos ARM64; autoriza la instalación desde el gestor de archivos. Es una compilación de desarrollo, firmada con la clave debug.

Para un APK optimizado, conserva la identidad de firma existente y configura
`android/key.properties` localmente con `storeFile`, `storePassword`, `keyAlias`
y `keyPassword`. Ejecuta
`flutter build apk --release --no-pub --target-platform android-arm64`.
Una compilación release sin configuración válida de firma falla expresamente.
Las claves y contraseñas están excluidas de Git. Para emuladores x64 usa
`--target-platform android-x64`.

GitHub Actions recibe los cuatro secretos Android mediante el contexto seguro,
restaura la keystore en un directorio temporal protegido y la elimina al terminar.
PR y ejecuciones manuales debug no necesitan secretos de release. Consulta
[firma y CI](docs/ci_signing.md) para nombres y configuración; no compartas claves
ni contraseñas en el chat. El ZIP Windows no tiene firma Authenticode.

## Arquitectura y seguridad

`lib/core/` define modelos y contratos; `lib/audio/` contiene SoLoud y controles
del sistema; `lib/sources/` integra yt-dlp; `lib/metadata/spotify/` consulta
metadatos; `lib/dj/` puntúa recomendaciones y aplica filtros; `lib/jam/` mantiene
sesiones LAN y audio temporal; `lib/ui/studio/` presenta el Atelier Sonoro; `lib/library/`
persiste la biblioteca; `lib/ui/` presenta las pantallas. `AppController`
coordina estado y reproducción. Consulta el [árbol de módulos](docs/architecture.md).

Los procesos reciben argumentos separados, con plugins/configuración externa desactivados; entradas YouTube restringidas a HTTPS y hosts permitidos. TLS permanece verificado, salidas/colas/buffers tienen límites y las descargas se publican por renombrado desde archivos temporales. Los mensajes ocultan consultas firmadas, cookies y autorización. No se guardan URLs de reproducción temporales.

Los archivos importados y descargados se guardan en el directorio de soporte de Aurora del usuario. Limpiar caché conserva la biblioteca; eliminar una descarga requiere confirmación. La app usa la salida de audio elegida por el sistema, incluidos auriculares cableados, USB o Bluetooth; las combinaciones físicas requieren pruebas de dispositivo.

## Validación

Consulta [docs/VALIDATION.md](docs/VALIDATION.md) para pruebas reproducibles, resultados y comprobaciones pendientes. El 2026-10-11 pasaron búsqueda, extracción, reproducción online, descarga MP3 y reproducción local en Windows, sin importar una sesión. El día anterior YouTube devolvió HTTP 429/verificación de cuenta: estos límites pueden reaparecer y no se garantiza disponibilidad de todos los videos o redes. El audio local funciona independientemente.
