import 'dart:async';

import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/utils/result.dart';

/// Persisted app-language selection shared by every window.
abstract interface class LanguageRepository {
  /// Completes after the initial persisted value has been hydrated.
  Future<Result<void>> get ready;

  AppLanguage get language;

  Stream<AppLanguage> watch();

  Future<Result<void>> setLanguage(AppLanguage value);

  void dispose();
}
