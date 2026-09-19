import 'package:pomodoist/data/repositories/planning/task_decomposition_repository.dart';
import 'package:pomodoist/data/services/planning/task_decomposer.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';

class SupabaseTaskDecomposer implements TaskDecomposer {
  SupabaseTaskDecomposer({
    required TaskDecompositionTransport transport,
    Duration fastTimeout = const Duration(seconds: 45),
    Duration smartTimeout = const Duration(seconds: 120),
  }) : _service = TaskDecompositionService(
         transport: transport,
         fastTimeout: fastTimeout,
         smartTimeout: smartTimeout,
       );

  final TaskDecompositionService _service;

  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) async {
    if (transcript.trim().isEmpty) return const [];
    return decodeTaskDecompositionResponse(
      await _service.request(
        transcript,
        now: now,
        locale: locale,
        smartMode: smartMode,
      ),
    );
  }
}
