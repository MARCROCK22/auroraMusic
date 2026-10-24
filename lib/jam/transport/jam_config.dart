import 'dart:convert';

/// Credenciales públicas del proyecto Supabase. Solo la clave anónima/publicable:
/// nunca service_role. Se leen con --dart-define (ver docs/jam_supabase.md).
class JamSupabaseConfig {
  const JamSupabaseConfig._(this.url, this.anonKey);
  final String url, anonKey;

  static const _url = String.fromEnvironment('AURORA_SUPABASE_URL');
  static const _key = String.fromEnvironment('AURORA_SUPABASE_ANON_KEY');

  /// Configuración compilada; null si falta algo o no es válido.
  static JamSupabaseConfig? get fromEnvironment => tryParse(_url, _key);

  /// Motivo legible por el que no hay configuración (null si está lista).
  static String? get environmentProblem => validate(_url, _key);

  static JamSupabaseConfig? tryParse(String url, String key) =>
      validate(url, key) == null
      ? JamSupabaseConfig._(url.trim(), key.trim())
      : null;

  /// Rechaza HTTP (solo TLS), URLs con credenciales y claves de servidor.
  /// Nunca incluye la clave en el mensaje devuelto.
  static String? validate(String url, String key) {
    url = url.trim();
    key = key.trim();
    if (url.isEmpty || key.isEmpty) {
      return 'La Jam en línea no está configurada. Compila con '
          'AURORA_SUPABASE_URL y AURORA_SUPABASE_ANON_KEY (docs/jam_supabase.md). '
          'La Jam por red local sigue disponible.';
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        !RegExp(r'^[a-z0-9.-]+$').hasMatch(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return 'La URL de Supabase debe ser https:// y sin credenciales.';
    }
    if (key.startsWith('sb_secret_')) {
      return 'Se rechazó una clave secreta. Usa solo la clave anónima/publicable.';
    }
    if (key.startsWith('sb_publishable_')) return null;
    final parts = key.split('.');
    if (parts.length != 3) return 'La clave anónima de Supabase no es válida.';
    try {
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map;
      if (payload['role'] != 'anon') {
        return 'Se rechazó una clave que no es anónima (¿service_role?). '
            'Usa solo la clave anónima.';
      }
    } catch (_) {
      return 'La clave anónima de Supabase no es válida.';
    }
    return null;
  }
}
