import 'dart:convert';

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

abstract class TaskDecomposer {
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  });
}

class TaskDecompositionException implements Exception {
  const TaskDecompositionException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef TaskDecompositionTransport =
    Future<Object?> Function(Map<String, Object?> body);

class SupabaseTaskDecomposer implements TaskDecomposer {
  SupabaseTaskDecomposer({
    required TaskDecompositionTransport transport,
    Duration fastTimeout = const Duration(seconds: 45),
    Duration smartTimeout = const Duration(seconds: 120),
  }) : _transport = transport,
       _fastTimeout = fastTimeout,
       _smartTimeout = smartTimeout;

  final TaskDecompositionTransport _transport;
  final Duration _fastTimeout;
  final Duration _smartTimeout;

  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) async {
    final text = transcript.trim();
    if (text.isEmpty) {
      return const <DecomposedTaskDraft>[];
    }
    Object? response;
    try {
      response = await _transport({
        'command': <String, Object?>{
          'type': 'task.decomposeTranscript',
          'transcript': text,
          'locale': locale,
          'currentLocalTime': _isoWithOffset(now),
          'smart': smartMode,
        },
      }).timeout(smartMode ? _smartTimeout : _fastTimeout);
    } on TaskDecompositionException {
      rethrow;
    } catch (error) {
      throw TaskDecompositionException('Task analysis failed: $error');
    }
    if (response is! Map) {
      throw const TaskDecompositionException(
        'Task analysis returned an invalid response.',
      );
    }
    if (response['ok'] == false) {
      throw TaskDecompositionException(
        response['error']?.toString() ?? 'Task analysis failed.',
      );
    }
    final tasks = _decodeTaskDrafts(response['tasks']);
    if (tasks.isEmpty) {
      throw const TaskDecompositionException(
        'Task analysis returned no task drafts.',
      );
    }
    return tasks;
  }
}

String _isoWithOffset(DateTime value) {
  final local = value.toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${local.toIso8601String()}$sign$hours:$minutes';
}

List<DecomposedTaskDraft> decodeDeepSeekTaskResponse(Object? payload) {
  final content = _chatContent(payload);
  if (content == null) {
    return const <DecomposedTaskDraft>[];
  }
  return decodeTaskJsonContent(content);
}

List<DecomposedTaskDraft> decodeTaskJsonContent(String content) {
  final slice = _jsonSlice(content.trim());
  if (slice == null) {
    return const <DecomposedTaskDraft>[];
  }
  final decoded = jsonDecode(slice);
  final tasks = decoded is Map ? decoded['tasks'] : decoded;
  return _decodeTaskDrafts(tasks);
}

List<DecomposedTaskDraft> _decodeTaskDrafts(Object? tasks) {
  if (tasks is! List) {
    return const <DecomposedTaskDraft>[];
  }
  final result = <DecomposedTaskDraft>[];
  final seen = <String>{};
  for (final task in tasks) {
    final draft = _decodeTaskDraft(task);
    if (draft == null || !seen.add(draft.quickAdd.toLowerCase())) {
      continue;
    }
    result.add(draft);
  }
  return result;
}

List<DecomposedTaskDraft> fallbackQuickAddTasks(String transcript) {
  return transcript
      .split(RegExp(r'[\n.;]+'))
      .map(_cleanTask)
      .where((task) => task.isNotEmpty)
      .map((task) => DecomposedTaskDraft(quickAdd: task))
      .toList();
}

DecomposedTaskDraft? _decodeTaskDraft(Object? task) {
  final text = switch (task) {
    String value => value,
    Map value =>
      value['quickAdd'] ??
          value['text'] ??
          value['task'] ??
          value['content'] ??
          value['title'],
    _ => null,
  };
  if (text is! String) {
    return null;
  }
  final quickAdd = _cleanTask(text);
  if (quickAdd.isEmpty) {
    return null;
  }
  final description = task is Map
      ? _cleanNullableTaskText(
          task['description'] ?? task['comment'] ?? task['note'],
        )
      : null;
  final subtasks = task is Map
      ? _decodeTaskDrafts(
          task['subtasks'] ??
              task['subTasks'] ??
              task['children'] ??
              task['steps'],
        )
      : const <DecomposedTaskDraft>[];
  return DecomposedTaskDraft(
    quickAdd: quickAdd,
    description: description,
    subtasks: subtasks,
  );
}

String? _chatContent(Object? payload) {
  final data = payload is String ? jsonDecode(payload) : payload;
  if (data is String) {
    return data;
  }
  if (data is Map) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] is String) {
          return message['content'] as String;
        }
        if (first['text'] is String) {
          return first['text'] as String;
        }
      }
    }
    if (data['tasks'] is List) {
      return jsonEncode(data);
    }
  }
  return null;
}

String? _jsonSlice(String content) {
  final unfenced = content
      .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();
  final objectStart = unfenced.indexOf('{');
  final objectEnd = unfenced.lastIndexOf('}');
  if (objectStart >= 0 && objectEnd > objectStart) {
    return unfenced.substring(objectStart, objectEnd + 1);
  }
  final listStart = unfenced.indexOf('[');
  final listEnd = unfenced.lastIndexOf(']');
  if (listStart >= 0 && listEnd > listStart) {
    return unfenced.substring(listStart, listEnd + 1);
  }
  return null;
}

String _cleanTask(String value) {
  return value
      .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String? _cleanNullableTaskText(Object? value) {
  if (value is! String) {
    return null;
  }
  final cleaned = _cleanTask(value);
  return cleaned.isEmpty ? null : cleaned;
}
