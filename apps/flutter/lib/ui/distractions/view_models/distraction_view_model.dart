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

// Hide release UI without disabling protection services or deleting saved profiles.
final blockingAvailableProvider = Provider<bool>((ref) => false);

({bool connected, bool applied}) distractionDeviceStatus(
  Map<String, dynamic> device, {
  required int? revision,
  required DateTime now,
}) {
  final seen = DateTime.tryParse('${device['lastSeenAt']}');
  final age = seen == null ? null : now.difference(seen);
  final connected =
      age != null && age >= Duration.zero && age < const Duration(seconds: 45);
  final caps = device['capabilities'] is Map
      ? device['capabilities'] as Map
      : const {};
  return (
    connected: connected,
    applied:
        connected &&
        device['detached'] != true &&
        revision != null &&
        device['appliedRevision'] == revision &&
        (caps['nativeApplied'] == true || caps['websiteApplied'] == true),
  );
}
