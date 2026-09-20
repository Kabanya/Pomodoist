import 'dart:async';

import 'package:pomodoist/data/repositories/focus/focus_completion_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';

final class DefaultFocusCompletionRepository
    implements FocusCompletionRepository {
  FocusRunCompletionEvent? _state;
  final _events = StreamController<FocusRunCompletionEvent?>.broadcast(
    sync: true,
  );
  @override
  FocusRunCompletionEvent? get state => _state;
  @override
  Stream<FocusRunCompletionEvent?> watch() => _events.stream;

  final Set<String> _presentedRunIds = <String>{};
  String? _actionRunId;

  void _publish(FocusRunCompletionEvent? value) {
    _state = value;
    _events.add(value);
  }

  @override
  void present(FocusRunCompletionEvent event) {
    if (!_presentedRunIds.add(event.runId)) {
      return;
    }
    _publish(event);
  }

  @override
  bool tryBeginAction(String runId) {
    if (_actionRunId != null || state?.runId != runId) return false;
    _actionRunId = runId;
    return true;
  }

  @override
  void endAction(String runId) {
    if (_actionRunId == runId) _actionRunId = null;
  }

  @override
  void dismiss({String? runId}) {
    if (runId != null && state?.runId != runId) return;
    _publish(null);
  }

  @override
  void dispose() {
    _events.close();
  }
}
