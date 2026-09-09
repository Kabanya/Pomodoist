import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/focus_models.dart';

final focusRunCompletionControllerProvider =
    NotifierProvider<FocusRunCompletionController, FocusRunCompletionEvent?>(
      FocusRunCompletionController.new,
    );

class FocusRunCompletionController extends Notifier<FocusRunCompletionEvent?> {
  final Set<String> _presentedRunIds = <String>{};
  String? _actionRunId;

  @override
  FocusRunCompletionEvent? build() => null;

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
