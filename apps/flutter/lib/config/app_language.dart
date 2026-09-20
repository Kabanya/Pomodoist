import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/language_repository.dart';
import 'package:pomodoist/data/repositories/settings/language_repository_impl.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';

final languageRepositoryProvider = Provider<LanguageRepository>((ref) {
  final repository = LocalLanguageRepository(
    ref.watch(preferencesServiceProvider),
    linked: kIsWeb
        ? AppLanguage.fromLanguageTag(Uri.base.queryParameters['lang'])
        : null,
  );
  ref.onDispose(repository.dispose);
  return repository;
});
final appLanguageProvider = Provider<AppLanguage>((ref) {
  final repository = ref.watch(languageRepositoryProvider);
  final subscription = repository.watch().listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  final observer = _LocaleObserver(ref.invalidateSelf);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
  return repository.language;
});

class _LocaleObserver extends WidgetsBindingObserver {
  _LocaleObserver(this.changed);
  final VoidCallback changed;
  @override
  void didChangeLocales(List<Locale>? locales) => changed();
}
