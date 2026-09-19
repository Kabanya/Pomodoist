import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pomodoist/utils/result.dart';

final class AccountProfileService {
  const AccountProfileService(this._client);

  final SupabaseClient _client;

  Future<Result<void>> updateNickname(String userId, String name) =>
      Result.capture(() async {
        if (_client.auth.currentUser?.id != userId) {
          throw StateError('The account session has changed.');
        }
        final value = name.trim();
        if (value.isEmpty) throw ArgumentError.value(name, 'nickname');
        await _client
            .from('profiles')
            .update({'display_name': value})
            .eq('id', userId)
            .select('id')
            .single();
      });
}
