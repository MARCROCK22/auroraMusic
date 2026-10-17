# Jam en línea con Supabase (plan gratis)

Estado: **no probado contra un proyecto real de Supabase.** El cliente se probó
con un transporte falso en memoria (`test/jam_remote_test.dart`); las políticas
RLS y las RPC de `docs/jam_supabase.sql` hay que probarlas en un proyecto real
con la lista de abusos de abajo antes de abrirlo a otras personas.

La Jam por red local (WebSocket en la LAN) sigue existiendo como respaldo y no
usa Supabase.

## 1. Crear el proyecto (gratis, sin tarjeta)

1. Entra en <https://supabase.com> → New project (plan Free). Región cercana.
2. Dashboard → **SQL Editor** → pega **todo** `docs/jam_supabase.sql` → Run.
3. Dashboard → **Project Settings → API**: copia **Project URL** y la clave
   **anon / publishable**. **Nunca** copies `service_role` ni `sb_secret_…`
   (la app rechaza esas claves).
4. (Opcional) Database → Extensions → **pg_cron** → Enable y descomenta la
   última sentencia del SQL para limpiar cada 15 min. Sin pg_cron, la limpieza
   de salas con 12 h sin actividad ocurre al crear o unirse a salas.

## 2. Poner las credenciales (solo en tu equipo)

Crea `dart_defines.json` en la raíz (está en `.gitignore`; no lo subas):

```json
{
  "AURORA_SUPABASE_URL": "https://TU-PROYECTO.supabase.co",
  "AURORA_SUPABASE_ANON_KEY": "TU_CLAVE_ANON"
}
```

Y compila/ejecuta con:

```powershell
$flutter = 'C:/flutter/flutter/bin/flutter.bat'
& $flutter run -d windows --dart-define-from-file=dart_defines.json
& $flutter build apk --release --dart-define-from-file=dart_defines.json
& $flutter build windows --release --dart-define-from-file=dart_defines.json
```

Sin esas dos variables, "Iniciar Jam en línea" queda deshabilitado con un
mensaje y la Jam por red local sigue funcionando. Las claves no van en código,
QR, enlaces ni logs. La clave anónima viaja dentro del binario (es pública por
diseño; la seguridad la dan RLS y las RPC).

## 3. Checklist del dashboard (obligatorio)

- **Authentication → Sign In / Providers**: activa **Allow anonymous sign-ins**;
  **desactiva** email, teléfono y todos los proveedores OAuth; desactiva
  "Allow new users to sign up" para métodos no anónimos.
- **Authentication → Rate Limits**: baja "Anonymous users" (p. ej. 30/hora por
  IP) y los de refresco de token.
- **Authentication → Attack Protection**: activa **CAPTCHA** (Turnstile o
  hCaptcha). Mientras el cliente no envíe `captchaToken` en `signInAnonymously`,
  CAPTCHA bloqueará los inicios: o lo dejas desactivado en esta fase y confías
  en los rate limits, o añades el token en `SupabaseJamTransport.signIn`
  (pendiente).
- **Project Settings → Realtime** (Realtime Settings): **desactiva "Allow
  public access"** (solo canales privados), y fija límites: conexiones
  concurrentes (plan gratis ~200), mensajes por segundo (p. ej. 20–50) y
  eventos por segundo por canal; tamaño máximo de mensaje.
- **Database → Roles / Settings**: no hay que tocar nada; el cliente solo usa
  `authenticated` con EXECUTE a las 14 RPC. Opcional: `statement_timeout` del
  rol authenticator ≤ 8 s.
- **Database → Backups/Logs**: revisa Logs → Postgres por `jam:` y errores
  repetidos; activa alertas de uso (egress, MAU anónimos).
- **Data API**: en *Settings → API → Exposed schemas* deja solo lo
  imprescindible; las tablas `jam_*` no tienen políticas, así que `/rest/v1/jam_*`
  devuelve vacío o 401.

## 4. Cómo funciona (resumen)

- Auth anónima (`signInAnonymously`) → `auth.uid()` identifica al dispositivo.
- Crear/unirse/añadir/votar/expulsar/permisos/transferir: **solo RPC**
  `SECURITY DEFINER` con `search_path = ''`, parámetros tipados y errores
  `jam:<código>` (nunca texto interno de Postgres).
- Canales Realtime privados `jam:<CÓDIGO>:down` (publican solo anfitrión y
  coanfitriones; todos los miembros leen y anuncian presencia) y
  `jam:<CÓDIGO>:up` (lo publica únicamente el servidor desde `jam_cmd`, con
  `from` verificado; solo el anfitrión lo lee).
- El anfitrión es la fuente de verdad de cola y reproducción; los invitados en
  modo *Escuchar* corrigen deriva ±1 s con el desfase estimado por ping/pong.
- Códigos de 6 caracteres sin ambiguos (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`),
  aleatorios en servidor. 5 fallos en 10 min → bloqueo 15 min. El anfitrión
  puede rotar el código, cerrar el acceso o bloquear reingresos.
- Sugerencias: cada dispositivo calcula **las suyas** con su propio perfil
  (radio de YouTube vía InnerTube `next` + ranking local) y publica solo 5
  pistas (ID + título/artista + razón) por minuto. Perfil, favoritos e
  historial no salen del dispositivo. El anfitrión intercala por turnos las
  listas, sin duplicados ni mismo artista seguido, y puede desactivarlas o
  exigir aprobación.

### Límites en servidor

| Concepto | Límite |
| --- | --- |
| Invitados por sala | 1–15 (+ anfitrión) |
| Salas activas por usuario | 1 como anfitrión; 3 como miembro |
| Crear salas | 3 por hora y usuario; 5000 salas en total |
| Unirse | 20 intentos / 10 min; 5 fallos de código → bloqueo 15 min |
| Comandos | 120/min por usuario, 600/min por sala; añadir 20/min; sugerir 1/min |
| Pistas añadidas por invitado | 200 por sala (el anfitrión fija el tope práctico) |
| Payload de comando | 6000 bytes; campos inesperados rechazados |
| Texto | nombre ≤ 32, título/artista ≤ 256, razón ≤ 60; sin caracteres de control ni marcas bidireccionales |
| ID de vídeo | `^[A-Za-z0-9_-]{11}$`; códigos `^[A-HJ-NP-Z2-9]{6}$` |
| Caducidad | 12 h sin actividad |

### Anti inyección SQL

- No hay SQL dinámico ni concatenación de entrada de usuario en sentencias;
  todo son parámetros tipados (`uuid`, `int`, `boolean`, `text`) y `CHECK`s.
- El cliente solo llama `.rpc()` con parámetros; no usa `.from()`, `.or()` ni
  `.filter()` con texto del usuario.
- Los errores devueltos son solo `jam:<código>` (regex de 3–12 letras); el
  cliente descarta cualquier otro mensaje.

### Anti abuso / DDoS (en capas)

1. Dashboard: rate limits de Auth, CAPTCHA, límites de Realtime (sección 3).
2. Servidor: ventanas fijas por usuario y por sala (`jam_hit`), bloqueo por
   fallos de código, tope de salas, `statement_timeout` por RPC.
3. Cliente: el anfitrión descarta más de 20 mensajes/s por invitado y limita
   10 solicitudes por 5 s; reconexión con backoff exponencial con jitter
   (1 s → 60 s) y sin bucles agresivos; sugerencias como máximo cada 60 s.

## 5. Casos de abuso a probar en el proyecto real

Prueba con dos sesiones anónimas distintas (usa `as_level`/clientes separados):

1. `select * from jam_rooms` / `jam_members` / `jam_rate` con la clave anónima
   (REST y PostgREST) → debe fallar o devolver vacío; `insert/update/delete`
   directos → denegado.
2. Llamar cualquier RPC sin sesión (rol `anon`) → denegado.
3. Fuerza bruta de códigos: 6 códigos inexistentes seguidos → `jam:rate`
   (bloqueo 15 min); el código válido durante el bloqueo también falla.
4. Enumeración: `jam_members` de una sala ajena → `jam:forbidden`; mensajes de
   error idénticos para sala inexistente y malformada.
5. Crear 4 salas en una hora y 2 salas a la vez → `jam:rate` / `jam:active`.
6. Unirse con la sala llena (16 miembros), cerrada (`jam_access`) o tras
   expulsión con bloqueo → `full` / `closed` / `banned`; tras `jam_rotate` el
   código viejo → `invalid`.
7. Invitado llama `jam_kick`, `jam_mute`, `jam_cohost`, `jam_access`,
   `jam_rotate`, `jam_transfer`, `jam_close` → `forbidden`. Coanfitrión no
   puede expulsar a otro coanfitrión ni al anfitrión.
8. `jam_claim_host` con el anfitrión activo → `forbidden`; sin latido > 60 s
   solo lo logra el miembro más antiguo.
9. Payloads hostiles en `jam_cmd`: `'; DROP TABLE jam_rooms;--`, `%`, `\u0000`,
   Unicode bidireccional, nombres de 10 000 caracteres, ID de vídeo de 12
   caracteres o con símbolos, JSON de más de 6000 bytes, claves extra
   (`kind`, `__proto__`), `v: 2`, `to: -1` → siempre `jam:payload`, sin
   efectos ni mensajes internos de Postgres.
10. Ráfaga: 200 `jam_cmd` en un minuto desde un usuario → `jam:rate`; dos
    `suggest` en 60 s → el segundo `jam:rate`; invitado silenciado que intenta
    `add`/`vote`/`suggest` → `jam:muted`.
11. Realtime: un invitado intenta publicar en `jam:CODE:down` (broadcast) →
    rechazado; cualquiera intenta publicar en `jam:CODE:up` → rechazado; un
    no-miembro se suscribe a `down`/`up` → rechazado; un invitado se suscribe a
    `up` → rechazado; canal público (`private: false`) → sin datos.
12. Caducidad: cambia `last_activity` de una sala a hace 13 h (como admin) y
    llama `jam_join`/`jam_cmd` → `jam:expired` y la sala se borra.
13. Que ninguna respuesta incluya claves, tokens, `service_role` ni trazas.

## 6. Enlaces `aurora://jam/CODIGO`

- **Android**: intent-filter VIEW/BROWSABLE para `aurora://jam` en
  `AndroidManifest.xml` (cambio aditivo). El enlace llega al activity; la app
  debe pasarlo a `JamController.joinFromLink(link, nombre)`.
- **Windows**: `registerAuroraProtocol()` (`lib/jam/jam_protocol.dart`, llamado
  en `main`) escribe `HKCU\Software\Classes\aurora` sin administrador.
- **Punto de integración con el frente 2 (instancia única)**: el segundo
  proceso lanzado por el protocolo recibe `aurora://jam/CODIGO` como argumento;
  el hook de instancia única debe reenviarlo a la instancia viva y esta llamar
  a `JamController.joinFromLink`. `jamCodeFromLaunchArgument(arg)` valida el
  argumento. El enlace solo lleva el código de 6 caracteres: ni claves ni URL.

## 7. Red local en Android

`dart:io` (WebSocket/HttpServer de la Jam LAN) usa sockets nativos y **no**
pasa por la Network Security Config de Android (que solo afecta a la pila HTTP
de Java/WebView). Por eso `ws://` a una IP privada funciona con
`cleartextTrafficPermitted="false"` global y `usesCleartextTraffic="false"`, sin
abrir texto claro. La app además solo acepta direcciones privadas
(`isJamAddress`). Hay que confirmarlo en un dispositivo real. El tráfico hacia
Supabase es `https://`/`wss://` únicamente (`JamSupabaseConfig` rechaza `http`).

## 8. Recomendaciones de YouTube / Auror

`JamSuggestionAdapter` (`lib/jam/jam_suggestions.dart`) pide a InnerTube la
radio (`next`, `InnerTubeSource.related`, sin clave ni tokens PO) de la pista
actual y de las dos últimas del historial **del propio dispositivo**, y las
reordena con un `rank` opcional. Integración con el frente 4: pasar como `rank`
una función que llame a `SuggestionsApi.getSuggestions(SessionContext)` con un
único `ParticipantTaste` (el perfil propio). Hoy `rank` es nulo (orden de
YouTube); si YouTube falla se usa la cola actual.

## Pendientes conocidos

- Probar SQL, RLS y Realtime en un proyecto real (no verificado).
- CAPTCHA en `signInAnonymously` (requiere token del widget).
- La sesión anónima no persiste entre reinicios (cada arranque = nuevo uid); si
  la app se cierra, el anfitrión pierde la sala hasta que caduque.
- Conectar `rank` con el frente 4 y llamar a `joinFromLink` desde el hook del
  frente 2.
