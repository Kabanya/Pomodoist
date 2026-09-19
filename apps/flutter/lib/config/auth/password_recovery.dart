import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:pomodoist/data/repositories/account/password_recovery_repository.dart';
import 'package:pomodoist/data/services/auth/password_recovery_service.dart';

final passwordRecoveryProvider =
    ChangeNotifierProvider<PasswordRecoveryRepository>((ref) {
      final baseUrl = ref.watch(runtimePublicConfigProvider).supabaseUrl;
      final controller = PasswordRecoveryRepository(
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
      ref.onDispose(() => service?.dispose());
      return controller;
    });
