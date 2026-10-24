import 'package:flutter_riverpod/legacy.dart';

import '../account/account_service.dart';
import 'friends_data.dart';
import 'friends_service.dart';

/// Amigos, ligado a la sesión de [accountServiceProvider].
final friendsServiceProvider = ChangeNotifierProvider<FriendsService>((ref) {
  final account = ref.read(accountServiceProvider);
  return FriendsService(
    auth: account,
    currentUid: () => account.profile?.id,
    dataFor: (uid) {
      final client = account.client;
      return client == null ? null : SupabaseFriendsData(client, uid);
    },
    avatarUrl: account.avatarUrlFor,
  );
});
