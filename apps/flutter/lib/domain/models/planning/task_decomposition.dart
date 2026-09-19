class DecomposedTaskDraft {
  const DecomposedTaskDraft({
    required this.quickAdd,
    this.description,
    this.subtasks = const [],
  });

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
