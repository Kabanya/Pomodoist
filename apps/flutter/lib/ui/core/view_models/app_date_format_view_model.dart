import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/settings/app_date_format.dart';

final appDateFormatProvider =
    NotifierProvider<AppDateFormatController, AppDateFormat>(
      AppDateFormatController.new,
    );

class AppDateFormatController extends Notifier<AppDateFormat> {
  late Future<void> ready;
  bool _edited = false;
  Future<void> _writes = Future.value();

  @override
  AppDateFormat build() {
    ready = _load();
    return AppDateFormat.automatic;
  }

  Future<void> _load() async {
    try {
      final saved = (await ref.read(preferencesRepositoryProvider).read([
        appDateFormatPreferenceKey,
      ])).getOrThrow();
      if (ref.mounted && !_edited) {
        state = AppDateFormat.fromStorageValue(
          saved[appDateFormatPreferenceKey],
        );
      }
    } catch (error) {
      debugPrint('Could not load date format: $error');
    }
  }

  Future<void> setFormat(AppDateFormat format) {
    final repository = ref.read(preferencesRepositoryProvider);
    final writing = _writes.then((_) async {
      (await repository.write({
        appDateFormatPreferenceKey: format.name,
      })).getOrThrow();
      _edited = true;
      if (ref.mounted) state = format;
    });
    _writes = writing.catchError((Object _) {});
    return writing;
  }
}
