import 'package:pomodoist/data/repositories/kanban/kanban_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';

import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';

Map<String, List<KanbanCard>> filterKanbanCards(
  Map<String, List<KanbanCard>> cards,
  String query, {
  String Function(ProjectItem project)? projectTitle,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return cards;
  }
  return {
    for (final entry in cards.entries)
      entry.key: entry.value
          .where(
            (card) =>
                card.task.content.toLowerCase().contains(normalized) ||
                card.project.name.toLowerCase().contains(normalized) ||
                (projectTitle != null &&
                    projectTitle(
                      card.project,
                    ).toLowerCase().contains(normalized)),
          )
          .toList(growable: false),
  };
}

KanbanBoardController createKanbanBoardController(WidgetRef ref) =>
    KanbanBoardController(ref.read(kanbanRepositoryProvider));

final kanbanScreenBoardProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(kanbanRepositoryProvider).watchBoard(),
);

final kanbanSelectedProjectsProvider = Provider.autoDispose
    .family<List<ProjectItem>, KanbanBoardSnapshot>((ref, board) {
      final ids = board.settings.selectedProjectIds.toSet();
      return List.unmodifiable(
        board.availableProjects.where((project) => ids.contains(project.id)),
      );
    });

final kanbanActiveFocusTaskIdProvider = Provider.autoDispose(
  (ref) => ref.watch(activeFocusRunProvider).value?.taskId,
);
final kanbanTaskTimeStateProvider = Provider.autoDispose.family(
  (ref, TaskItem task) => ref.watch(taskTimeStateProvider(task)),
);
final kanbanTaskTimeDisplayModeProvider = Provider.autoDispose(
  (ref) => ref.watch(taskTimeDisplayModeProvider),
);
final kanbanDefaultTimedBlockMinutesProvider = Provider.autoDispose(
  (ref) => ref.watch(quickAddDefaultTimedBlockMinutesProvider),
);
final kanbanFocusRemainingProvider = Provider.autoDispose(
  (ref) => ref.watch(activeFocusRemainingProvider),
);
final kanbanFocusIntervalProvider = Provider.autoDispose(
  (ref) => ref.watch(activeFocusIntervalProvider),
);

Future<void> setKanbanSelectedProjects(
  WidgetRef ref,
  Set<String> selected,
) async {
  (await ref.read(kanbanRepositoryProvider).setSelectedProjectIds(selected))
      .getOrThrow();
}

Future<void> startKanbanFocus(WidgetRef ref, KanbanCard card) async {
  (await ref
          .read(focusRepositoryProvider)
          .startRun(
            StartFocusRunInput(
              taskId: card.task.id,
              projectId: card.project.id,
              targetWorkIntervals: card.task.estimatedFocusIntervals,
            ),
          ))
      .getOrThrow();
}

Future<void> stopKanbanFocus(WidgetRef ref) async {
  (await ref
          .read(focusRepositoryProvider)
          .stopActiveRun(reason: StopFocusReason.stopped))
      .getOrThrow();
}

class KanbanDragPayload {
  const KanbanDragPayload({
    required this.taskId,
    required this.sourceStatusId,
    required this.sourceIndex,
    required this.token,
  });

  final String taskId;
  final String sourceStatusId;
  final int sourceIndex;
  final int token;
}

class KanbanOptimisticOverride {
  const KanbanOptimisticOverride({
    required this.token,
    required this.statusId,
    this.targetIndex,
  });

  final int token;
  final String statusId;
  final int? targetIndex;
}

class KanbanBoardController extends ChangeNotifier {
  KanbanBoardController(this._repository);

  final KanbanRepository _repository;
  final Map<String, KanbanOptimisticOverride> _overrides = {};
  final Map<String, int> _tokens = {};
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Map<String, KanbanOptimisticOverride> get overrides =>
      Map.unmodifiable(_overrides);

  int nextDragToken(String taskId) => (_tokens[taskId] ?? 0) + 1;

  Map<String, List<KanbanCard>> visibleCards(
    KanbanBoardSnapshot snapshot, {
    String query = '',
    String Function(ProjectItem project)? projectTitle,
  }) {
    final result = {
      for (final status in snapshot.statuses)
        status.id: List<KanbanCard>.from(snapshot.cardsForStatus(status.id)),
    };
    for (final entry in _overrides.entries) {
      KanbanCard? card;
      for (final cards in result.values) {
        final index = cards.indexWhere(
          (candidate) => candidate.task.id == entry.key,
        );
        if (index >= 0) {
          card = cards.removeAt(index);
          break;
        }
      }
      final target = result[entry.value.statusId];
      if (card == null || target == null) {
        continue;
      }
      final insertionIndex = (entry.value.targetIndex ?? target.length).clamp(
        0,
        target.length,
      );
      target.insert(insertionIndex, card);
    }
    return filterKanbanCards(result, query, projectTitle: projectTitle);
  }

  Future<void> moveTask(
    String taskId, {
    required String statusId,
    int? targetIndex,
  }) async {
    final token = (_tokens[taskId] ?? 0) + 1;
    _tokens[taskId] = token;
    _overrides[taskId] = KanbanOptimisticOverride(
      token: token,
      statusId: statusId,
      targetIndex: targetIndex,
    );
    _notify();
    try {
      (await _repository.moveTask(
        taskId,
        statusId: statusId,
        targetIndex: targetIndex,
      )).getOrThrow();
    } catch (_) {
      if (_overrides[taskId]?.token == token) {
        _overrides.remove(taskId);
        _notify();
      }
      rethrow;
    }
  }

  void reconcile(KanbanBoardSnapshot snapshot) {
    var changed = false;
    for (final entry in _overrides.entries.toList()) {
      final cards = snapshot.cardsForStatus(entry.value.statusId);
      final index = cards.indexWhere((card) => card.task.id == entry.key);
      final targetIndex = entry.value.targetIndex;
      final acknowledged =
          index >= 0 &&
          (targetIndex == null ||
              index == targetIndex.clamp(0, cards.length - 1));
      if (acknowledged) {
        _overrides.remove(entry.key);
        changed = true;
      }
    }
    if (changed) {
      _notify();
    }
  }
}
