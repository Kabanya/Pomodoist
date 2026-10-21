/// A successful local completion. This is ephemeral, not synchronized history.
class LocalCompletionEvent {
  const LocalCompletionEvent({
    required this.operationId,
    required this.entityId,
    required this.isTask,
  });
  final String operationId, entityId;
  final bool isTask;
}
