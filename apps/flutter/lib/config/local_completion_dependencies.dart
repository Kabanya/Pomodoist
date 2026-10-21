import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/domain/models/tasks/local_completion_event.dart';

final localCompletionEventsProvider = Provider<LocalCompletionEvents>((ref) {
  final events = LocalCompletionEvents();
  ref.onDispose(events.dispose);
  return events;
});

class LocalCompletionEvents {
  final _events = StreamController<LocalCompletionEvent>.broadcast();
  Stream<LocalCompletionEvent> get stream => _events.stream;
  void publish(LocalCompletionEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void dispose() => unawaited(_events.close());
}
