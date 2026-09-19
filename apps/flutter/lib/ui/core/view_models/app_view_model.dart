import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/platform/platform_quick_add.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';

final class AppViewState {
  const AppViewState({required this.language});

  final AppLanguage language;
}

final appViewModelProvider = Provider<AppViewState>((ref) {
  ref.watch(accountLocaleSyncProvider);
  ref.watch(platformQuickAddControllerProvider);
  return AppViewState(language: ref.watch(appLanguageProvider));
});
