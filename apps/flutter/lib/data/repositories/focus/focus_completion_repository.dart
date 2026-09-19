import 'package:flutter/foundation.dart';

import 'package:pomodoist/domain/models/focus/focus_models.dart';

class FocusCompletionRepository extends ChangeNotifier {
  FocusRunCompletionEvent? _state;
  FocusRunCompletionEvent? get state => _state;
  set state(FocusRunCompletionEvent? value) {
    _state = value;
    notifyListeners();
  }

  final Set<String> _presentedRunIds = <String>{};
  String? _actionRunId;

  void present(FocusRunCompletionEvent event) {
    if (!_presentedRunIds.add(event.runId)) {
      return;
    }
    state = event;
  }

  bool tryBeginAction(String runId) {
    if (_actionRunId != null || state?.runId != runId) return false;
    _actionRunId = runId;
    return true;
  }

  void endAction(String runId) {
    if (_actionRunId == runId) _actionRunId = null;
  }

  void dismiss({String? runId}) {
    if (runId != null && state?.runId != runId) return;
    state = null;
  }
}
