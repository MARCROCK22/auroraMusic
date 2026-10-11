# Validación de Aurora

## Entorno y alcance

Windows x64, Flutter 3.38.8 / Dart 3.10.7; Android API 36.1 en emulador x86_64. La plataforma mínima configurada es Android API 24. Las pruebas de emulador no sustituyen pruebas en teléfonos o auriculares físicos.

## Pruebas reproducibles

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter test integration_test/interface_smoke_test.dart -d windows --no-pub
flutter test integration_test/app_smoke_test.dart -d windows --no-pub
flutter test integration_test/app_smoke_test.dart -d <android-id> --no-pub
flutter test integration_test/audio_smoke_test.dart -d windows --no-pub --dart-define=AURORA_TOOLS=C:/ruta/tools/windows --name "native WAV|FFmpeg PCM"
flutter test integration_test/audio_smoke_test.dart -d <android-id> --no-pub --name "native WAV|FFmpeg PCM"
flutter test integration_test/audio_smoke_test.dart -d windows --no-pub --dart-define=AURORA_SOAK_MINUTES=30 --plain-name "native audio soak"
```

Las pruebas nativas generan tonos de volumen bajo y archivos temporales, que eliminan al finalizar. No ejecutes dos compilaciones Windows simultáneamente sobre el mismo directorio de salida.

La comprobación online es explícita porque depende del proveedor:

```powershell
flutter test integration_test/source_smoke_test.dart -d windows --no-pub --dart-define=AURORA_ONLINE_SMOKE=true --dart-define=AURORA_TOOLS=C:/ruta/tools/windows --dart-define=AURORA_SAMPLE_URL=https://www.youtube.com/watch?v=jNQXAC9IVRw
```

Usa un video público permitido para probar extracción, reproducción y descarga. El archivo de prueba no se conserva.

## Resultados

| Comprobación | Resultado |
| --- | --- |
| Unitarias y widgets | 60 pruebas aprobadas: cola y duplicados, carreras asíncronas, cierre, restauración, biblioteca, carpeta de descargas persistente, borrado seguro, letras y caché/importación, sesión opcional, DSP, layouts, contraste y prevención de búsquedas duplicadas. |
| Rediseño y centrado | Capturas nativas a 1440×900 y 390×844; navegación, biblioteca, búsqueda, descargas, ajustes, vinilo, cola y letras. Botón de reproducción centrado a 1440/900 dp; metadatos móviles separados de controles; disco, etiqueta y agujero del vinilo concéntricos con tolerancia de 1 dp, también a 320 dp con texto al 200 %. |
| Layouts | 320, 800 y 1440 dp; texto al 200%; reproductor, cola y EQ; confirmar/cancelar borrado. |
| Contraste | 24 tonos de portada en temas claro/oscuro; acciones y texto ≥4,5:1. |
| Audio Windows | WAV y PCM FFmpeg aprobados: reloj consumido, pausa, seek, FFT, RMS del EQ, buffer reciclado, cambios rápidos y EOF. |
| Arranque Windows | Base SQLite, audio, EQ inicialmente apagado, controles multimedia e interfaz sin error. Herramientas preparadas al compilar y detectadas automáticamente; diagnóstico yt-dlp aprobado. |
| Arranque Android | Base SQLite, audio y pantalla principal aprobados en emulador. |
| Audio Android | WAV y PCM FFmpeg aprobados: pausa, seek, FFT, EQ, cancelación y EOF. Excepción de cierre del worker corregida y comprobada. |
| Reproducción continua Windows | Ejecutable release independiente: 30 minutos aprobados, 1801 s de reloj consumido, crecimiento máximo de memoria de 909312 bytes. Log `build/native_audio_soak_release_30min.jsonl`, evento final `complete`. |
| YouTube Windows (2026-10-11) | Búsqueda por texto y extracción CLI aprobadas sin sesión. Prueba nativa aprobada con `jNQXAC9IVRw`: metadatos, extracción HTTPS, reproducción real, descarga MP3, reproducción local y seek. El bloqueo 429 observado el día anterior no se reprodujo hoy; el resultado no garantiza disponibilidad de todos los videos o redes. |
| Paquetes del rediseño | Windows release: `dist/redisenado/Aurora-Windows.zip`, herramientas/licencias incluidas; hash del motor release verificado y ejecutable independiente activo tras cinco segundos de arranque. Android ARM64: `dist/redisenado/Aurora-Android-arm64-debug.apk`, firma de desarrollo. Ambos tienen archivos SHA-256. Las comprobaciones online y de audio de las filas anteriores corresponden a la validación previa del motor, conservado en este rediseño. |
| Alineación Android | ZIP de 16 KB y 265 ELF ARM64, incluyendo dependencias archivadas Python/FFmpeg: aprobados. WebP recompilado y avisos de licencia presentes en APK. |

La inspección de dependencias detectó cinco ELF WebP de 4 KB dentro del archivo FFmpeg original. `scripts/rebuild_android_webp.ps1` recompila esas bibliotecas desde código oficial con NDK 28 y verifica sus símbolos/SONAME; `scripts/verify_android_alignment.ps1` revisa tanto las bibliotecas visibles del APK como las dependencias archivadas de Python/FFmpeg. La comprobación estática y la ejecución en un dispositivo de 16 KB son verificaciones diferentes.

Para repetir la prueba larga sin depender de la conexión del depurador:

```powershell
flutter build windows --release --no-pub -t integration_test/audio_soak_runner.dart --dart-define=AURORA_SOAK_MINUTES=30 --dart-define=AURORA_SOAK_LOG=C:/ruta/aurora-soak.jsonl
$env:AURORA_HIDE_WINDOW='1'
Start-Process ./build/windows/x64/runner/Release/aurora_music.exe -WindowStyle Hidden -Wait
# Restaurar el ejecutable de la aplicación después de la prueba:
flutter build windows --release --no-pub -t lib/main.dart
```

El runner escribe muestras cada 10 segundos y eventos `complete`/`failed`; el código de salida es 0/1. Durante esta implementación se ejecutó una copia aislada en `build/soak-runner-bin`, permitiendo compilar la aplicación simultáneamente.

Los logs de ejecución quedan en `build/` y los artefactos en `dist/`; ambos están excluidos de Git.

El rediseño se verificó con `build/ui-union-tests.log` (60 pruebas),
`build/ui-analyze.log`, `build/interface-native.log`,
`build/app-native-redesign.log` y `build/android-redesign-alignment.log`.
Las capturas `build/screenshots/aurora-redesign-*.png` utilizan audio simulado y
portadas geométricas originales para comparar el diseño sin datos personales;
la prueba de arranque utiliza SQLite y el motor de audio nativos.

La búsqueda se envía solo con Enter o la flecha. La prueba de interfaz comprueba que escribir y repetir Enter durante una consulta pendiente no duplique solicitudes. La importación de sesión es voluntaria: valida Netscape y cookies de YouTube, conserva el original, protege cambios durante operaciones activas y no expone valores en errores. No se probó con credenciales reales de un usuario.

## Matriz de dispositivos pendiente

En un teléfono real y en Windows, comprobar con un archivo local y una fuente online disponible:

- Auriculares cableados, USB y Bluetooth: reproducción, pausa, controles, cambios de salida y desconexión sin reproducción inesperada.
- Android: pantalla bloqueada, segundo plano, llamada entrante, pérdida/recuperación de foco, restricciones de batería y notificación multimedia.
- Windows: controles SMTC/teclas multimedia, cambio de dispositivo predeterminado y suspensión/reanudación.
- Descarga: pérdida de red, poco espacio, cancelación, reinicio de app y reproducción completamente sin conexión.
- Teléfono con páginas de 16 KB: instalación, arranque, extracción, seek y reproducción; revisar también alineación ELF y ZIP del APK.
- Distribución: instalar APK firmado con clave privada; verificar actualización conservando biblioteca. Extraer ZIP Windows en equipo limpio y ejecutar diagnóstico sin Python instalado.

No se declara compatibilidad universal con modelos de auriculares ni certificación de hardware a partir de estas pruebas automatizadas.
