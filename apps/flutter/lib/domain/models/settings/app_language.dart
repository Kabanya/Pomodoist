const appLanguagePreferenceKey = 'app.language';

enum AppLanguage {
  system(null, 'System default'),
  en('en', 'English'),
  ru('ru', 'Русский'),
  de('de', 'Deutsch'),
  es('es', 'Español'),
  fr('fr', 'Français'),
  ar('ar', 'العربية'),
  zh('zh', '简体中文'),
  ptBR('pt-BR', 'Português (Brasil)'),
  ja('ja', '日本語'),
  ko('ko', '한국어');

  const AppLanguage(this.languageTag, this.nativeName);

  final String? languageTag;
  final String nativeName;

  String get storageValue => name;

  static AppLanguage? fromLanguageTag(String? value) {
    if (value == null ||
        !RegExp(r'^[a-zA-Z]{2,3}(?:[-_][a-zA-Z0-9]{2,8})*$').hasMatch(value)) {
      return null;
    }
    final base = value.toLowerCase().split(RegExp('[-_]')).first;
    for (final language in values) {
      if (language.languageTag?.split('-').first == base) return language;
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
