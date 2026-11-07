import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:pomodoist/config/task_blocking_dependencies.dart'
    show
        taskBlockingActionsProvider,
        taskBlockingConflictsProvider,
        taskBlockingPolicyProvider;

class InlineTaskDeleteRequests
    extends Notifier<Map<String, Future<void> Function()>> {
  @override
  Map<String, Future<void> Function()> build() => {};
  void request(String id, Future<void> Function() action) =>
      state = {...state, id: action};
  void clear(String id) => state = {...state}..remove(id);
}

final inlineTaskDeleteRequestsProvider =
    NotifierProvider<
      InlineTaskDeleteRequests,
      Map<String, Future<void> Function()>
    >(InlineTaskDeleteRequests.new);
