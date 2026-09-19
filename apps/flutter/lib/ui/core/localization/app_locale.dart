import 'package:flutter/widgets.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';

extension AppLanguageLocale on AppLanguage {
  Locale? get locale {
    final tag = languageTag;
    if (tag == null) return null;
    final parts = tag.split('-');
    return Locale(parts.first, parts.length > 1 ? parts[1] : null);
  }
}

Locale resolveAppLocale(AppLanguage language, {List<Locale>? systemLocales}) {
  if (language.locale != null) return language.locale!;
  final requested =
      systemLocales ?? WidgetsBinding.instance.platformDispatcher.locales;
  for (final locale in requested) {
    final match = AppLanguage.fromLanguageTag(locale.toLanguageTag());
    if (match != null) return match.locale!;
  }
  return const Locale('en');
}
