import 'package:pomodoist/domain/models/planning/quick_add_hint.dart';

/// Shared hint history, refresh policy and retry state, independent of views.
abstract interface class QuickAddHintRepository {
  QuickAddHintState get state;

  /// Emits subsequent snapshots; read [state] for the current value.
  Stream<QuickAddHintState> watch();

  Future<void> initialize();
  Future<void> recordUserTaskCreated();
  void dispose();
}
