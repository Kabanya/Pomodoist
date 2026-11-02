import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'dart:convert';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';

SharedScope? sharedScopeFromRow(SharedScopeRow? row) =>
    row == null ? null : SharedScope.fromJson(jsonDecode(row.dataJson));

TaskItem taskItemFromRow(TaskRow row, {SharedScope? scope}) => TaskItem(
  scopeId: row.scopeId,
  createdBy: row.createdBy,
  completedBy: row.completedBy,
  prerequisiteIds: List<String>.from(
    jsonDecode(row.prerequisiteIdsJson) as List,
  ),
  assigneeIds: collaborationIds(row.assigneeIdsJson),
  canEdit: row.scopeId == null || (scope?.canEdit ?? false),
  id: row.id,
  userId: row.userId,
  content: row.content,
  description: row.description,
  projectId: row.projectId,
  sectionId: row.sectionId,
  parentId: row.parentId,
  priority: row.priority,
  dueJson: row.dueJson,
  deadlineJson: row.deadlineJson,
  durationSeconds: row.durationSeconds,
  status: row.status,
  estimatedFocusIntervals: row.estimatedFocusIntervals,
  isFocusEstimateManual: row.isFocusEstimateManual,
  completedFocusIntervals: row.completedFocusIntervals,
  totalFocusSeconds: row.totalFocusSeconds,
  orderKey: row.orderKey,
  dayOrder: row.dayOrder,
  isCollapsed: row.isCollapsed,
  isDeleted: row.isDeleted,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  completedAt: row.completedAt,
);
