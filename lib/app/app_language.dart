import 'dart:async';

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
  zh(Locale('zh'), '简体中文');

  const AppLanguage(this.locale, this.nativeName);

  final Locale? locale;
  final String nativeName;

  String get storageValue => name;

  static AppLanguage fromStorageValue(String? value) {
    return AppLanguage.values.firstWhere(
      (language) => language.storageValue == value,
      orElse: () => AppLanguage.system,
    );
  }
}

final appLanguageProvider =
    NotifierProvider<AppLanguageController, AppLanguage>(
      AppLanguageController.new,
    );

class AppLanguageController extends Notifier<AppLanguage> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  AppLanguage build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredLanguage());
    }
    return AppLanguage.system;
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
    final stored = AppLanguage.fromStorageValue(
      prefs.getString(appLanguagePreferenceKey),
    );
    if (ref.mounted && !_hasLocalSelection) {
      state = stored;
    }
  }
}
