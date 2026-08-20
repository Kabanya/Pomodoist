import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/focus_models.dart';

final focusRunCompletionControllerProvider =
    NotifierProvider<FocusRunCompletionController, FocusRunCompletionEvent?>(
      FocusRunCompletionController.new,
    );

class FocusRunCompletionController extends Notifier<FocusRunCompletionEvent?> {
  final Set<String> _presentedRunIds = <String>{};

  @override
  FocusRunCompletionEvent? build() => null;

  void present(FocusRunCompletionEvent event) {
    if (!_presentedRunIds.add(event.runId)) {
      return;
    }
    state = event;
  }

  void dismiss() {
    state = null;
  }
}
