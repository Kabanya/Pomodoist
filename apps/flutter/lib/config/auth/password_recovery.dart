import 'package:pomodoist/domain/models/account/password_recovery.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:pomodoist/data/repositories/account/password_recovery_repository.dart';
import 'package:pomodoist/data/repositories/account/password_recovery_repository_impl.dart';
import 'package:pomodoist/data/services/auth/password_recovery_service.dart';

final passwordRecoveryProvider = Provider<PasswordRecoveryRepository>((ref) {
  final baseUrl = ref.watch(runtimePublicConfigProvider).supabaseUrl;
  final controller = SdkPasswordRecoveryRepository(
    locale: () =>
        resolveAppLocale(ref.read(appLanguageProvider)).toLanguageTag(),
  );
  PasswordRecoveryService? service;
  ref.listen(accountClientProvider, (_, account) {
    service?.dispose();
    service = account == null || baseUrl == null
        ? null
        : PasswordRecoveryService(
            auth: Supabase.instance.client.auth,
            userEndpoint: baseUrl.replace(
              path:
                  '${baseUrl.path.replaceAll(RegExp(r'/+$'), '')}/auth/v1/user',
            ),
          );
    controller.attach(service);
  }, fireImmediately: true);
  ref.onDispose(() {
    service?.dispose();
    controller.dispose();
  });
  return controller;
});

final passwordRecoveryStateProvider = StreamProvider<PasswordRecoveryState>(
  (ref) => ref.watch(passwordRecoveryProvider).watchState(),
);
