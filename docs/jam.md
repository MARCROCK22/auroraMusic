# Jam local

Jam vive en memoria y se activa desde su pantalla. No requiere servidor remoto,
cuenta ni migración de base de datos; la cola personal se conserva aparte.

## Crear y unirse

1. En Aurora, abre Jam y elige Crear Jam. Selecciona la dirección privada de tu
   Wi-Fi o Ethernet y un nombre opcional para la sesión.
2. Pulsa Iniciar sesión local. Aurora abre un puerto en esa interfaz concreta y
   muestra un QR temporal. El anfitrión puede copiar la invitación explícitamente.
3. En el otro dispositivo, abre Jam y escanea el QR. Android permite cámara;
   Windows permite importar una imagen QR o pegar la invitación copiada.
4. Si se corta la conexión, Reconectar recupera la misma identidad y permisos
   mientras el anfitrión conserve la sesión. Salir invalida esa reconexión.
5. Cerrar Jam invalida sus accesos, desconecta participantes y cierra el servidor.
   El QR vence tras cuatro horas como máximo; crea otra sesión para renovar acceso.

No se abre red ni cámara al iniciar Aurora o visitar Jam. La cámara se solicita
únicamente al abrir Escanear QR. Windows puede mostrar un aviso del firewall al
crear el servidor; habilita Aurora en una red privada de confianza. Los errores
incluyen comprobaciones de Wi-Fi, firewall y aislamiento de clientes del router.
No cambies el router ni abras puertos a Internet para usar esta función.

## Dos modos

**Cola compartida:** todos agregan canciones y reciben el estado autoritativo del
anfitrión por WebSocket. Cada canción indica quién la agregó. Se evitan duplicados
por identificador canónico de YouTube, URI de Spotify y título/artista normalizados.
El anfitrión decide individualmente permisos para omitir, reordenar y quitar;
reproducir, pausar, elegir canción y buscar una posición siguen siendo del anfitrión.
La cola funciona sin sincronía ni disponibilidad de audio en todos los equipos.

**Reproducción sincronizada:** el anfitrión activa el modo y los invitados eligen
Reproducir en este dispositivo. Cada dispositivo resuelve audio con sus propios
proveedores y biblioteca. Solo se comparten metadatos públicos y el identificador
canónico, nunca archivos locales, URLs extraídas, cookies, cabeceras ni credenciales.
Si un archivo local no está en la biblioteca del invitado, se muestra un aviso y
el resto de la sesión continúa. Una búsqueda de catálogo requiere coincidencia
normalizada exacta de artista y título; no se reproduce una coincidencia incierta.

El estado incluye pista, play/pausa, posición, secuencia y tiempo del anfitrión.
Ping/pong estima el desfase de reloj; el anfitrión emite un estado cada segundo.
La carga inicial comienza en la posición estimada. Después, se ignoran diferencias
menores de 750 ms y se ajustan hasta 500 ms cada cinco segundos. No se recarga una
pista al recibir estados repetidos. Se limita a cinco segundos la extrapolación
de estados antiguos. El motor actual no permite cambiar velocidad: la sincronía
es aproximada y las correcciones pueden tomar tiempo tras una búsqueda grande.
Distintas versiones, silencios iniciales, búferes y latencias de proveedor impiden
prometer sincronización exacta. Aurora lo explica en la pantalla.

La reproducción Jam usa un overlay temporal de audio. Se suspende el reproductor
personal con su posición; no se reemplaza su cola por la compartida. Al salir,
la escucha personal que estaba reproduciéndose se reanuda si su canción permanece
en la cola, conservando las ediciones posteriores. Una cola previamente pausada
permanece pausada. El DJ personal se detiene al activar este overlay.

## Límites y protección

- Solo IPv4 privada literal RFC1918; no DNS, IP pública, wildcard, IPv6 ni red remota.
  El loopback se habilita exclusivamente como opción inyectada en pruebas.
- Token aleatorio de 256 bits y sesión temporal; acceso por Authorization del
  handshake, nunca en query strings. La reconexión usa un secreto independiente
  por participante. No se sirven páginas web ni se aceptan orígenes de navegador.
- Hasta 16 identidades por sesión (incluye autores desconectados para mantener la
  atribución), 200 canciones, 10 solicitudes por participante en cinco segundos.
  Mensajes inválidos también cuentan; el exceso desconecta al emisor.
- Comandos limitados a ocho KiB; snapshots a un MiB; campos, tipos, relaciones,
  identificadores, URLs y permisos se validan. No se imprimen invitaciones ni tokens.
- Imágenes QR limitadas a ocho MiB y cuatro megapíxeles antes de decodificar píxeles.
  Las portadas compartidas aceptan únicamente HTTPS sin query ni credenciales y
  hosts de imágenes de YouTube/Spotify conocidos.

La conexión LAN WebSocket y el QR no están cifrados. Un observador en esa red puede
ver metadatos y acceso temporal: utiliza una red de confianza y cierra la sesión
cuando termines. No hay descubrimiento automático, túnel remoto ni UPnP.

## Dependencias y plataformas

- [zxing2 0.2.4](https://pub.dev/packages/zxing2): generación y lectura QR en Dart,
  licencia BSD-3-Clause. Flutter decodifica la imagen, reutilizando el selector de
  archivos existente; no se añade otro paquete de imágenes ni lector nativo Windows.
- [mobile_scanner 7.4.2](https://pub.dev/packages/mobile_scanner): lector de cámara
  Android, BSD-3-Clause. Su ML Kit está empaquetado para escanear sin descargar un
  modelo en la primera sesión; aumenta el tamaño de la aplicación. El paquete no
  ofrece cámara Windows y la interfaz muestra claramente la alternativa de imagen.
- [Permiso LAN Android](https://developer.android.com/privacy-and-security/local-network-permission):
  con target SDK <=36, INTERNET permite esta red sin otro permiso runtime.
  Al actualizar a target >=37 será necesario declarar y solicitar
  ACCESS_LOCAL_NETWORK al activar Crear/Unir Jam. No se pide ahora ese permiso ni
  NEARBY_WIFI_DEVICES. CAMERA es opcional y se solicita por el escáner bajo demanda.
- [Política de red Flutter](https://docs.flutter.dev/release/breaking-changes/network-policy-ios-android):
  las conexiones de Dart usan sus propios sockets; no se habilita tráfico cleartext
  global ni se cambia TLS de los proveedores de audio y metadatos.

Los avisos de licencia de las dependencias forman parte de las licencias Flutter.
La sesión no garantiza funcionamiento en routers con aislamiento de clientes,
VPN, redes corporativas o permisos de firewall denegados. No se ha verificado
cámara, dos dispositivos físicos ni Bluetooth durante esta implementación.

## Organización y pruebas

`lib/jam/` contiene modelos/protocolo, servidor/cliente, controlador, puente de
reproducción y lectura QR. `lib/ui/jam/` contiene pantalla de conexión, paneles de
sesión, QR y diálogo de cámara. No se persisten participantes, tokens ni colas Jam.

La suite `test/jam_*_test.dart` usa sockets loopback locales y fuentes/audio falsos:
creación/unión/cierre, cola y autoría, permisos, duplicados, rate limit, mensajes
inválidos, expiración, reconexión, errores, reloj y desfase, audio ausente,
cancelación de cargas antiguas y conservación de la cola personal. La lectura QR
incluye una imagen generada por Flutter; las pruebas de interfaz cubren activación
bajo demanda, error de invitación, ancho móvil y texto ampliado. No contacta con
Spotify ni proveedores de audio externos.

## Autoplay y añadir en lote (v2)

- `JamRules.autoplay` (true por defecto, lo cambia el anfitrión). Con menos de 3 pistas en cola normal por delante, el anfitrión sube a la cola (`JamService.promoteSuggested`) las sugerencias «A continuación», ya intercaladas por participante, sin duplicados ni artista seguido. Las pendientes de aprobación no se promueven. Cada entrada lleva `suggestedFor`.
- Cada dispositivo publica sus sugerencias (máx. 5, 1 por minuto) al entrar, al cambiar la pista y por temporizador; sin red caen a lo local. El perfil nunca sale del equipo.
- `JamService.addMany` / `JamController.addTracks` / `addPlaylist`: el anfitrión inserta directo (tope 200 en la cola); los invitados envían lotes de 5 cada 15,5 s (el servidor admite 20 `add`/min y 200 por sala) con tope `maxPerGuest`. Se informa qué se descartó. «Siguiente/Ahora» solo para el anfitrión.
- No hace falta volver a ejecutar `jam_supabase.sql`: el anfitrión es la fuente de verdad y ninguna RPC cambia.
