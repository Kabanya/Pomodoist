import 'package:pomodoist/domain/models/platform/global_shortcut.dart';
export 'package:pomodoist/domain/models/platform/global_shortcut.dart';

/// Domain-facing global shortcut state and actions. The platform channel and
/// window handles stay in the implementation; ViewModels use this contract.
abstract interface class GlobalQuickAddRepository {
  GlobalQuickAddState get state;
  Future<void> get ready;
  Stream<GlobalQuickAddState> watchState();
  Future<void> setEnabled(bool enabled);
  Future<void> setShortcut(GlobalQuickAddBinding shortcut);
  Future<GlobalQuickAddBinding> captureShortcut();
  Future<void> cancelCapture();
}
