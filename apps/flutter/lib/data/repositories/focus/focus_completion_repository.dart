import 'package:pomodoist/domain/models/focus/focus_models.dart';

/// Application-session owner of focus-run completion events.
///
/// Deduplicates by run id and serializes completion actions so a completion is
/// presented and acted on at most once across routes and windows. [state] is
/// the current snapshot, [watch] delivers later updates, and per-screen
/// animation phases stay in the screen's ViewModel.
abstract interface class FocusCompletionRepository {
  FocusRunCompletionEvent? get state;

  Stream<FocusRunCompletionEvent?> watch();

  void present(FocusRunCompletionEvent event);

  bool tryBeginAction(String runId);

  void endAction(String runId);

  void dismiss({String? runId});

  void dispose();
}
