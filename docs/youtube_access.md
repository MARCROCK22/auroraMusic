# Acceso a YouTube: investigación y recuperación

Revisión del 13 de octubre de 2026. No existe un cambio en Aurora que pueda
garantizar que YouTube acepte todas las solicitudes: la decisión de acceso
pertenece al servicio. Sí se pueden corregir errores del extractor y evitar
que Aurora genere solicitudes innecesarias o diagnostique un bloqueo falso.

## Evidencia de Aurora

La prueba real en Android inicia yt-dlp nightly `2026.10.10.233141`, Python,
QuickJS y FFmpeg en el emulador x86_64. La resolución del vídeo público produjo
un mensaje de verificación/posible restricción y se detuvieron los intentos.
El registro conserva el mensaje resumido, no la respuesta HTTP original: **no
permite concluir si fue 429, verificación de sesión o un bloqueo de toda la IP**.
Tampoco demuestra que descargar audio haya causado el problema.

En esta revisión no se hicieron nuevas peticiones a YouTube. Windows ejecuta
localmente la nightly y Deno `2.9.7`; Android empaqueta EJS y QuickJS. Confirmar
su presencia no demuestra que puedan resolver cada desafío remoto actual.

## Qué puede resolver cada causa

| Señal comprobada | Recuperación posible | Límite |
| --- | --- | --- |
| Fallo del extractor después de un cambio de YouTube | Actualizar yt-dlp nightly mediante el actualizador verificado existente | No elimina una restricción del servicio |
| Runtime JavaScript o EJS faltante/incompatible | Reparar el empaquetado y comprobar versiones | No equivale a solucionar una comprobación antibot |
| 403 de una URL con fecha `expire`/`expires` ya vencida | Resolver una URL nueva una sola vez y conservar la posición | Un 403 por sí solo no prueba expiración |
| Mensaje explícito de token de origen faltante | Investigar la integración de un proveedor PO Token compatible | No es un desbloqueador de IP; tokens ligados a sesión/vídeo y soporte cambiante |
| 429, verificación antibot o límite de sesión | Detener solicitudes, respetar la pausa y comprobar el servicio desde su interfaz oficial | No hay un plazo publicado que garantice recuperar acceso |
| Vídeo privado, eliminado o restringido por país | Informar que ese contenido no está disponible | No debe bloquear las demás búsquedas |

La documentación de yt-dlp describe PO Tokens y proveedores mantenidos por
terceros. No se añadieron: el registro no demuestra que falte un token, y el
flujo solicitado conserva yt-dlp sin suplantar clientes ni recurrir a cuentas,
cookies, proxies, VPN o rotación de IP para evadir restricciones. EJS ya viene
incluido en los ejecutables oficiales usados por Aurora; habilitar descargas
remotas de scripts no es necesario para reparar un paquete que lo incluye.

## Verificación de esta revisión

`flutter test`: 306 pruebas aprobadas. `flutter analyze`: sin incidencias.
`:app:testDebugUnitTest`: cuatro pruebas Kotlin aprobadas, incluida la
construcción real de argumentos con `--sleep-requests 1` y sin reintentos.
La nightly Windows acepta esos argumentos y devuelve su versión sin consultar
YouTube. Las pruebas del minuto cubren 59/60 segundos, persistencia y reducción
de pausas antiguas. No sustituyen una resolución real aceptada por YouTube.
`flutter build apk --debug` también compiló correctamente con estos cambios.

## Correcciones aplicadas

- La clasificación compartida exige un código HTTP reconocible; números en
  identificadores, nombres de archivos o parámetros de URLs no activan una
  pausa falsa. También reconoce el límite de sesión documentado como
  `This content isn't available, try again later`.
- Fuente y controlador usan esa misma clasificación. Un 429 se registra y
  detiene la recuperación aunque una URL almacenada ya haya vencido.
- El aviso explica que el minuto de espera es una pausa de Aurora y que YouTube
  puede mantener su restricción más tiempo. Un 403 no prueba un bloqueo de red.
- Se mantienen caché, agrupación de peticiones iguales, dos operaciones
  simultáneas como máximo y espera entre inicios. Además, `--sleep-requests 1`
  espera un segundo entre las peticiones internas de extracción de yt-dlp en
  ambas plataformas; no añade descargas a la reproducción normal ni limita
  la velocidad del stream de ExoPlayer. El contador mide invocaciones
  del extractor, no cada petición HTTP interna a YouTube.

Estas correcciones evitan bloqueos falsos y reintentos indebidos; **no se afirma
que hayan eliminado la restricción observada en la prueba real**. Las canciones
locales y descargadas continúan disponibles durante la pausa. Su vencimiento
no dispara una petición automática: permite la siguiente acción del usuario.

## Cómo distinguir el problema sin bombardear el servicio

1. Durante la pausa, usa archivos locales; no fuerces repetidos intentos.
2. Abre el mismo vídeo público en YouTube oficial desde la misma conexión.
   Si solicita una verificación, sigue la interfaz oficial. No hace falta
   exportar ni compartir credenciales para esta comprobación.
3. Si allí reproduce y Aurora sigue fallando, hay una diferencia entre ambos
   flujos. Puede ser el extractor o una restricción selectiva; no descarta por
   completo límites de sesión/red ni demuestra que falte un PO Token.
4. Comprueba la versión de yt-dlp en Ajustes. Tras la pausa, realiza una sola
   acción de reproducción. Si vuelve a rechazarse, detén los intentos y espera
   más; ningún intervalo garantiza acceso.

Fuentes primarias:
[errores frecuentes](https://github.com/yt-dlp/yt-dlp/wiki/FAQ),
[extractor de YouTube y límites de sesión](https://github.com/yt-dlp/yt-dlp/wiki/Extractors),
[JavaScript y EJS](https://github.com/yt-dlp/yt-dlp/wiki/EJS),
[opciones de espera](https://github.com/yt-dlp/yt-dlp#workarounds),
[tokens de origen](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide).
