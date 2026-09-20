class DecomposedTaskDraft {
  DecomposedTaskDraft({
    required this.quickAdd,
    this.description,
    List<DecomposedTaskDraft> subtasks = const [],
  }) : subtasks = List.unmodifiable(subtasks);

  final String quickAdd;
  final String? description;
  final List<DecomposedTaskDraft> subtasks;
}

class TaskDecompositionException implements Exception {
  const TaskDecompositionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Split a transcript into editable drafts when analysis returns nothing.
List<DecomposedTaskDraft> fallbackQuickAddTasks(String transcript) {
  return transcript
      .split(RegExp(r'[\n.;]+'))
      .map(_cleanFallbackTask)
      .where((task) => task.isNotEmpty)
      .map((task) => DecomposedTaskDraft(quickAdd: task))
      .toList();
}

String _cleanFallbackTask(String value) => value
    .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
