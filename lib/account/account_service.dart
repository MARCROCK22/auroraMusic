import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase/supabase.dart';

/// STUB TEMPORAL: el servicio real lo aporta la rama «cuentas».
class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.username,
    this.avatarUrl,
  });
  final String id;
  final String username;
  final String? avatarUrl;
}

class AccountService extends ChangeNotifier {
  bool get available => false;
  SupabaseClient? get client => null;
  AccountProfile? get profile => null;
  bool get signedIn => profile != null;
  String? avatarUrlFor(String? avatarPath) => null;
}

final accountServiceProvider = ChangeNotifierProvider<AccountService>(
  (ref) => AccountService(),
);
