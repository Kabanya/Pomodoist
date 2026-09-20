import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists account metadata that is not part of the local preference model.
final class AccountLocaleService {
  const AccountLocaleService();

  Future<void> sync(String locale) async {
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser == null ||
        auth.currentUser?.userMetadata?['pomodoist_locale'] == locale) {
      return;
    }
    await auth.updateUser(UserAttributes(data: {'pomodoist_locale': locale}));
  }
}
