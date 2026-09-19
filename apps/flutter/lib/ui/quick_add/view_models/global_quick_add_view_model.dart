import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';

final quickAddWindowLanguageProvider = Provider<AppLanguage>(
  (ref) => ref.watch(appLanguageProvider),
);
