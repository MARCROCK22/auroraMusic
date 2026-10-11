# Aurora

Reproductor de música en Flutter y Dart para **Windows x64 y Android 7+**. Interfaz en español, biblioteca local y fuentes públicas de YouTube mediante yt-dlp ejecutado en el dispositivo.

## Funciones

- Inicio, búsqueda, importación de enlaces/listas de YouTube y archivos locales.
- Favoritos, playlists editables, historial y cola reordenable; aleatorio, repetición, volumen, avance y temporizador.
- Descargas MP3 con progreso, cancelación, reintento y eliminación; biblioteca disponible sin conexión.
- Colores extraídos de la portada, ambiente reactivo a la energía y visualizador FFT del audio real.
- Ecualizador DSP de ocho bandas, presets y reducción automática de ganancia para los refuerzos.
- Controles multimedia del sistema, servicio de audio Android, pausa por desconexión e interrupciones de audio.
- SQLite local; restaura cola y posición **en pausa**. Temas claro/oscuro/sistema y movimiento reducido.

No hay cuentas, sincronización, catálogo de Spotify, DRM, letras ni recomendaciones de un servicio remoto.

## Ejecutar desde el código

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

Para un APK optimizado, crea una clave privada y configura `android/key.properties`:

```properties
storeFile=C:/ruta/privada/aurora.jks
storePassword=TU_PASSWORD
keyAlias=aurora
keyPassword=TU_PASSWORD
```

Después ejecuta `flutter build apk --release --no-pub --target-platform android-arm64`. Sin ese archivo, release queda **sin firma**. Conserva la misma clave para futuras actualizaciones; las claves y contraseñas están excluidas de Git. Para emuladores x64 usa `--target-platform android-x64`.

## Arquitectura y seguridad

`lib/core/` define modelos y contratos; `lib/audio/` contiene SoLoud y controles del sistema; `lib/sources/` integra yt-dlp; `lib/ui/` presenta las pantallas. `AppController` coordina estado y `LibraryDatabase` persiste metadatos.

Los procesos reciben argumentos separados, con plugins/configuración externa desactivados; entradas YouTube restringidas a HTTPS y hosts permitidos. TLS permanece verificado, salidas/colas/buffers tienen límites y las descargas se publican por renombrado desde archivos temporales. Los mensajes ocultan consultas firmadas, cookies y autorización. No se guardan URLs de reproducción temporales.

Los archivos importados y descargados se guardan en el directorio de soporte de Aurora del usuario. Limpiar caché conserva la biblioteca; eliminar una descarga requiere confirmación. La app usa la salida de audio elegida por el sistema, incluidos auriculares cableados, USB o Bluetooth; las combinaciones físicas requieren pruebas de dispositivo.

## Validación

Consulta [docs/VALIDATION.md](docs/VALIDATION.md) para pruebas reproducibles, resultados y comprobaciones pendientes. El 2026-10-11 pasaron búsqueda, extracción, reproducción online, descarga MP3 y reproducción local en Windows, sin importar una sesión. El día anterior YouTube devolvió HTTP 429/verificación de cuenta: estos límites pueden reaparecer y no se garantiza disponibilidad de todos los videos o redes. El audio local funciona independientemente.
