import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';

final bottomNavigationProvider =
    AsyncNotifierProvider<
      BottomNavigationController,
      BottomNavigationPreferences
    >(BottomNavigationController.new);

class BottomNavigationController
    extends AsyncNotifier<BottomNavigationPreferences> {
  bool _saving = false;

  @override
  Future<BottomNavigationPreferences> build() async {
    final values = (await ref.watch(preferencesRepositoryProvider).read([
      bottomNavigationPreferenceKey,
    ])).getOrThrow();
    return BottomNavigationPreferences.decode(
      values[bottomNavigationPreferenceKey],
    );
  }

  Future<void> save(BottomNavigationPreferences next) async {
    if (_saving) throw StateError('Navigation save already in progress');
    _saving = true;
    try {
      // Finish the initial read before writing so it cannot overwrite this save.
      await future;
      if (!ref.mounted) return;
      (await ref.read(preferencesRepositoryProvider).write({
        bottomNavigationPreferenceKey: next.encode(),
      })).getOrThrow();
      if (ref.mounted) state = AsyncData(next);
    } finally {
      _saving = false;
    }
  }
}
