import 'package:app_account/app_account.dart';
import '../db/app_database.dart' show kanbanSettingsPrimaryId;

Map<String, dynamic> syncDataWithoutSyncMetadata(JsonMap data) {
  return Map<String, dynamic>.from(data)
    ..remove('schemaVersion')
    ..remove('commandType');
}

Map<String, dynamic> syncMergeRow(
  Map<String, dynamic>? existing,
  Map<String, dynamic> incoming,
) {
  return <String, dynamic>{...?existing, ...incoming};
}

DateTime? syncDateTimeFromSyncValue(Object? value) {
  return switch (value) {
    final DateTime dateTime => dateTime.toUtc(),
    final int milliseconds => DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ),
    final num milliseconds => DateTime.fromMillisecondsSinceEpoch(
      milliseconds.toInt(),
      isUtc: true,
    ),
    final String text => DateTime.tryParse(text)?.toUtc(),
    _ => null,
  };
}

bool syncHasRequired(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (!data.containsKey(key) || data[key] == null) {
      return false;
    }
  }
  return true;
}

String syncEntityTypeForCommand(String commandType) {
  if (commandType.startsWith('focus_contribution.')) return 'focus_interval';
  if (commandType == 'task.kanbanStatus.set') {
    return 'task_kanban_status';
  }
  if (commandType.startsWith('kanban.settings.')) {
    return 'kanban_settings';
  }
  if (commandType.startsWith('kanban.status.')) {
    return 'label';
  }
  if (commandType == 'google_calendar.connection.upsert' ||
      commandType == 'google_calendar.connection.delete') {
    return 'google_calendar_connection';
  }
  if (commandType == 'google_calendar.link.upsert' ||
      commandType == 'google_calendar.link.delete') {
    return 'google_calendar_event_link';
  }
  if (commandType == 'task.label.add' || commandType == 'task.label.delete') {
    return 'task_label';
  }
  if (commandType.startsWith('focus.run.')) {
    return 'focus_run';
  }
  if (commandType.startsWith('focus.interval.')) {
    return 'focus_interval';
  }
  if (commandType.startsWith('focus.preset.')) {
    return 'focus_preset';
  }
  if (commandType == 'focus.distraction.log') {
    return 'focus_event';
  }
  return switch (commandType.split('.').first) {
    'project' => 'project',
    'section' => 'section',
    'task' => 'task',
    'label' => 'label',
    'filter' => 'filter',
    'reminder' => 'reminder',
    _ => commandType.split('.').first,
  };
}

String syncEntityIdForCommand(
  ({String id, String? clientId, String uuid}) command,
  Map<String, Object?> payload,
  String entityType,
) {
  if (entityType == 'task_kanban_status') {
    return payload['taskId'] as String? ?? command.clientId ?? command.id;
  }
  if (entityType == 'kanban_settings') {
    return payload['id'] as String? ?? kanbanSettingsPrimaryId;
  }
  if (entityType == 'task_label') {
    final taskId = payload['taskId'] as String? ?? command.clientId ?? '';
    final labelId = payload['labelId'] as String? ?? '';
    return syncTaskLabelEntityId(taskId, labelId);
  }
  if (entityType == 'focus_event') {
    return (payload['id'] as String?) ?? command.uuid;
  }
  if (entityType == 'google_calendar_connection') {
    return (payload['id'] as String?) ?? 'primary';
  }
  if (entityType == 'google_calendar_event_link') {
    return (payload['taskId'] as String?) ?? command.clientId ?? command.id;
  }
  return (payload['id'] as String?) ??
      (payload['runId'] as String?) ??
      command.clientId ??
      command.id;
}

SyncTaskLabelIds? syncTaskLabelIdsFromEntity(AccountSyncEntity entity) {
  return syncTaskLabelIds(
    entity.entityId,
    syncDataWithoutSyncMetadata(entity.data),
  );
}

SyncTaskLabelIds? syncTaskLabelIds(String entityId, Map<String, dynamic> data) {
  final taskId = data['taskId'] as String?;
  final labelId = data['labelId'] as String?;
  if (taskId != null && labelId != null) {
    return SyncTaskLabelIds(taskId, labelId);
  }
  final separator = entityId.indexOf(':');
  if (separator <= 0 || separator == entityId.length - 1) {
    return null;
  }
  return SyncTaskLabelIds(
    entityId.substring(0, separator),
    entityId.substring(separator + 1),
  );
}

String syncTaskLabelEntityId(String taskId, String labelId) =>
    '$taskId:$labelId';

bool syncUsesCapturedPatch(String commandType) {
  return commandType == 'task.update' ||
      commandType == 'task.move' ||
      commandType == 'task.complete' ||
      commandType == 'task.uncomplete' ||
      commandType == 'task.kanbanStatus.set' ||
      commandType == 'task.reorder' ||
      commandType == 'kanban.status.rename' ||
      commandType == 'kanban.status.reorder' ||
      commandType.startsWith('kanban.settings.');
}

Map<String, Object?> syncCapturedPatchPayload(
  String commandType,
  Map<String, Object?> payload,
  DateTime updatedAt,
) {
  final timestamp = updatedAt.toUtc().millisecondsSinceEpoch;
  if (commandType == 'task.complete') {
    return {
      'id': payload['id'],
      'status': 'completed',
      'completedAt': payload['completedAt'],
      'updatedAt': timestamp,
    };
  }
  if (commandType == 'task.uncomplete') {
    return {
      'id': payload['id'],
      'status': 'open',
      'completedAt': null,
      'updatedAt': timestamp,
    };
  }
  if (commandType == 'task.update') {
    final patch = Map<String, Object?>.from(payload);
    if (patch.containsKey('due')) {
      patch['dueJson'] = patch.remove('due');
      patch.putIfAbsent('durationSeconds', () => null);
    }
    patch['updatedAt'] = timestamp;
    return patch;
  }
  if (commandType == 'task.move') {
    return {...payload, 'updatedAt': timestamp};
  }
  return payload;
}

class SyncTaskLabelIds {
  const SyncTaskLabelIds(this.taskId, this.labelId);

  final String taskId;
  final String labelId;
}
