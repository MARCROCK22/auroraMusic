# 403 / 400 en la reproducción de Android

Alcance: sin cambiar el motor (InnerTube VISIONOS -> AudioProxy -> Media3).

## Causa raíz (analizada en código y tests; sin dispositivo)

1. **400 no se renovaba.** googlevideo responde 400 a URLs caducadas o con
   parámetros que ya no casan; `AudioProxy._open` solo renovaba 401/403/410, así
   que un 400 acababa como 410 hacia Media3 sin reintento ni marca del cliente.
2. **Caducidad optimista.** `expiresAt` salía solo de `expiresInSeconds`; la URL
   lleva su propio `expire` firmado, que puede ser anterior. El proxy seguía
   usando una URL ya rechazada hasta recibir el 403/400.
3. **Reintentos de Media3.** `DefaultLoadErrorHandlingPolicy` solo omitía el
   reintento para 403/429; con 400/410 (el proxy ya renovó una vez) reintentaba
   en vano.
4. El reporte `reportPlaybackFailure` ignoraba el 400.

## Cambios

- `audio_proxy.dart`: 400 entra en el conjunto de renovación única (como 403).
- `stream_orchestrator.dart`: `expiresAt = min(expiresInSeconds, expire de la
  URL)`; 400 cuenta como fallo de autorización para la lista negra del cliente.
- `innertube_source.dart`: el reporte reconoce 400.
- `AuroraPlaybackService.kt`: sin reintento nativo para 400/403/410/429.
- Tests: `audio_proxy_test.dart` (servidor falso con 400 y 403),
  `stream_orchestrator_test.dart` (parámetro `expire`).

## Limitaciones

- La tabla solo tiene VISIONOS: no hay cliente alternativo real al que saltar;
  añadir uno exige verificar que devuelve URLs sin cifrar (`tool/probe_innertube_clients.dart`).
- Sin backoff adicional: se renueva una vez por trozo (single-flight) y luego 410.
- Verificado solo con tests y servidor HTTP simulado; no hubo adb/dispositivo.
