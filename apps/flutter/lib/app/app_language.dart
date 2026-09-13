import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const appLanguagePreferenceKey = 'app.language';

enum AppLanguage {
  system(null, 'System default'),
  en(Locale('en'), 'English'),
  ru(Locale('ru'), 'Русский'),
  de(Locale('de'), 'Deutsch'),
  es(Locale('es'), 'Español'),
  fr(Locale('fr'), 'Français'),
  ar(Locale('ar'), 'العربية'),
  zh(Locale('zh'), '简体中文'),
  ptBR(Locale('pt', 'BR'), 'Português (Brasil)'),
  ja(Locale('ja'), '日本語'),
  ko(Locale('ko'), '한국어');

  const AppLanguage(this.locale, this.nativeName);

  final Locale? locale;
  final String nativeName;

  String get storageValue => name;

  static AppLanguage? fromLanguageTag(String? value) {
    if (value == null ||
        !RegExp(r'^[a-zA-Z]{2,3}(?:[-_][a-zA-Z0-9]{2,8})*$').hasMatch(value)) {
      return null;
    }
    final base = value.toLowerCase().split(RegExp('[-_]')).first;
    for (final language in values) {
      if (language.locale?.languageCode == base) return language;
    }
    return null;
  }

  static AppLanguage fromStorageValue(String? value) {
    return AppLanguage.values.firstWhere(
      (language) => language.storageValue == value,
      orElse: () => AppLanguage.system,
    );
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

final appLanguageProvider =
    NotifierProvider<AppLanguageController, AppLanguage>(
      AppLanguageController.new,
    );

class AppLanguageController extends Notifier<AppLanguage>
    with WidgetsBindingObserver {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  AppLanguage build() {
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addObserver(this);
      ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
      unawaited(_loadStoredLanguage());
    }
    return AppLanguage.system;
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (state == AppLanguage.system) ref.notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    _hasLocalSelection = true;
    if (state != language) {
      state = language;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(appLanguagePreferenceKey, language.storageValue);
  }

  Future<void> _loadStoredLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final linked = kIsWeb
        ? AppLanguage.fromLanguageTag(Uri.base.queryParameters['lang'])
        : null;
    final stored =
        linked ??
        AppLanguage.fromStorageValue(prefs.getString(appLanguagePreferenceKey));
    if (ref.mounted && !_hasLocalSelection) {
      state = stored;
      if (linked != null) {
        await prefs.setString(appLanguagePreferenceKey, linked.storageValue);
      }
    }
  }
}
