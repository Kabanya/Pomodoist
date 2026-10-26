import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/distraction_dependencies.dart';
import 'package:pomodoist/data/repositories/distractions/distraction_repository.dart';
export 'package:pomodoist/data/repositories/distractions/distraction_repository.dart'
    show DistractionSettingsState;

final distractionViewModelProvider = Provider<DistractionSettingsState>((ref) {
  final repo = ref.watch(distractionRepositoryProvider);
  final sub = repo?.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(() => sub?.cancel());
  return repo?.state ?? const DistractionSettingsState();
});
final distractionCommandsProvider = Provider<DistractionRepository?>(
  (ref) => ref.watch(distractionRepositoryProvider),
);
