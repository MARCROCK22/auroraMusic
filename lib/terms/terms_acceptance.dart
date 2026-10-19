import 'package:shared_preferences/shared_preferences.dart';

import 'terms_text.dart';

/// Aceptación de los términos guardada en local. Rechazar no persiste nada.
class TermsAcceptance {
  TermsAcceptance(this._preferences, {this.version = kTermsVersion});

  static const versionKey = 'terms.acceptedVersion';
  static const dateKey = 'terms.acceptedAt';

  final SharedPreferences _preferences;
  final String version;

  bool get isAccepted => _preferences.getString(versionKey) == version;

  Future<void> accept({DateTime? now}) async {
    await _preferences.setString(
      dateKey,
      (now ?? DateTime.now()).toUtc().toIso8601String(),
    );
    await _preferences.setString(versionKey, version);
  }
}
