import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pomodoist/data/services/auth/email_auth_service.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/app_language.dart';

final emailAuthProvider = Provider<EmailAuthController>((ref) {
  final account = ref.watch(accountClientProvider);
  return EmailAuthController(
    account == null ? null : Supabase.instance.client.auth,
    locale: () =>
        resolveAppLocale(ref.read(appLanguageProvider)).toLanguageTag(),
  );
});
