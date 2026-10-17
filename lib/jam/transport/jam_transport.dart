import 'dart:async';
import 'dart:convert';
import '../jam_models.dart';

/// Tope de un mensaje de canal. Supabase Realtime admite 256 KB por mensaje en
/// el plan gratis; dejamos margen.
const jamMaxEnvelopeBytes = 200 * 1024;

/// Mensaje entre anfitrión y pares. Anfitrión→invitados viaja en el canal
/// `down` (solo el anfitrión puede publicar); invitados→anfitrión llega por el
/// canal `up`, que **publica el servidor** (RPC jam_cmd) con `from` verificado.
class JamEnvelope {
  const JamEnvelope({required this.from, required this.to, required this.text});

  /// uid de quien envía (auth.uid() en Supabase).
  final String from;

  /// uid destinatario o `*` (todos).
  final String to;
  final String text;
  Map<String, Object> toJson() => {'f': from, 't': to, 'm': text};

  /// Valida cualquier entrada recibida; nunca ejecuta nada de ella.
  static JamEnvelope? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final f = raw['f'], t = raw['t'], m = raw['m'];
    if (f is! String ||
        t is! String ||
        m is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(f) ||
        !(t == '*' || RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(t)) ||
        m.length > jamMaxEnvelopeBytes ||
        utf8.encode(m).length > jamMaxEnvelopeBytes) {
      return null;
    }
    return JamEnvelope(from: f, to: t, text: m);
  }
}

class JamPresenceEvent {
  const JamPresenceEvent(this.uid, {required this.joined});
  final String uid;
  final bool joined;
}

/// Sala de mensajería. Para el anfitrión [incoming] trae lo de los invitados y
/// [send] publica hacia ellos; para un invitado es al revés.
abstract class JamChannel {
  Stream<JamEnvelope> get incoming;

  /// Presencia del canal `down` (el anfitrión también la anuncia).
  Stream<JamPresenceEvent> get presence;
  Stream<bool> get online;
  bool get isOnline;
  Future<void> send(JamEnvelope envelope);
  Future<void> track();
  Future<void> close();
}

class JamRoomInfo {
  const JamRoomInfo({
    required this.code,
    required this.hostUid,
    required this.expiresAt,
    this.role = JamRole.guest,
  });
  final String code, hostUid;
  final DateTime expiresAt;
  final JamRole role;
}

class JamMemberRow {
  const JamMemberRow({
    required this.uid,
    required this.name,
    required this.role,
    required this.muted,
    required this.joinedAt,
  });
  final String uid, name;
  final JamRole role;
  final bool muted;
  final DateTime joinedAt;
}

/// Códigos de error de servidor → mensaje para el usuario.
String jamRemoteMessage(String code) => switch (code) {
  'invalid' => 'Ese código no existe. Revísalo con quien creó la Jam.',
  'expired' => 'La Jam caducó por inactividad o ya terminó.',
  'full' => 'La Jam está llena.',
  'banned' => 'El anfitrión bloqueó tu reingreso a esta Jam.',
  'closed' => 'El anfitrión cerró el acceso a esta Jam.',
  'rate' => 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.',
  'forbidden' => 'No tienes permiso para esa acción.',
  'active' => 'Ya tienes una Jam activa. Ciérrala antes de crear otra.',
  'limit' => 'Alcanzaste el límite de la Jam.',
  'muted' => 'El anfitrión te silenció en esta Jam.',
  'payload' => 'Datos de Jam inválidos.',
  'network' => 'Sin conexión con el servicio de Jam.',
  _ => 'No se pudo completar la acción de Jam.',
};

class JamRemoteException extends JamException {
  JamRemoteException(this.code) : super(jamRemoteMessage(code));
  final String code;
}

/// Servicio remoto. Todas las operaciones privilegiadas son RPC del servidor
/// que validan auth.uid(), rol, sala y límites (docs/jam_supabase.sql).
abstract class JamTransport {
  /// Falso si faltan credenciales; [unavailableReason] explica por qué.
  bool get available;
  String? get unavailableReason;

  /// Identidad anónima de este dispositivo (se crea al primer uso).
  Future<String> signIn();
  Future<JamRoomInfo> createRoom({
    required String name,
    required String device,
  });
  Future<JamRoomInfo> joinRoom({
    required String code,
    required String name,
    required String device,
  });
  Future<List<JamMemberRow>> members(String code);
  Future<void> heartbeat(String code, {bool activity = false});

  /// Acción de invitado: el servidor valida, limita y la reenvía al anfitrión.
  Future<void> command(String code, String kind, Map<String, Object?> payload);
  Future<void> leave(String code);
  Future<void> closeRoom(String code);
  Future<void> kick(String code, String uid, {bool ban = false});
  Future<void> setMuted(String code, String uid, bool muted);
  Future<void> setCoHost(String code, String uid, bool coHost);
  Future<void> setAccess(
    String code, {
    required bool open,
    required int maxGuests,
  });
  Future<String> rotateCode(String code);
  Future<void> transferHost(String code, String uid);
  Future<JamRoomInfo> claimHost(String code);
  JamChannel openChannel(String code, {required bool asHost});
}
