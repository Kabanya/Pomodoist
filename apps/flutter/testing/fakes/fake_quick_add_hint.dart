import 'package:pomodoist/data/services/planning/quick_add_hint.dart';

import 'strict_fake.dart';

/// In-memory [QuickAddHintHistory] double.
///
/// Reads answer from the mutable fields below, every call is recorded in its
/// `<method>Calls` list, and a call whose `<method>Error` field is non-null
/// throws that error instead of succeeding.
class FakeQuickAddHintHistory extends StrictFake
    implements QuickAddHintHistory {
  /// Count [countExistingUserTasks] succeeds with.
  int taskCount = 0;

  /// Titles [recentTaskTitles] answers from, truncated to the requested limit.
  List<String> titles = const [];

  /// When non-null, the matching method throws it.
  Object? countExistingUserTasksError;
  Object? recentTaskTitlesError;

  /// Limits passed to [recentTaskTitles].
  final recentTaskTitlesCalls = <({int limit})>[];

  final countExistingUserTasksCalls = <void>[];

  @override
  Future<int> countExistingUserTasks() async {
    countExistingUserTasksCalls.add(null);
    final error = countExistingUserTasksError;
    if (error != null) throw error;
    return taskCount;
  }

  @override
  Future<List<String>> recentTaskTitles({required int limit}) async {
    recentTaskTitlesCalls.add((limit: limit));
    final error = recentTaskTitlesError;
    if (error != null) throw error;
    return titles.take(limit).toList();
  }
}

/// In-memory [QuickAddHintGenerator] double.
///
/// [generate] answers with [hint] unless [generateError] is set, and records
/// every call in [generateCalls].
class FakeQuickAddHintGenerator extends StrictFake
    implements QuickAddHintGenerator {
  /// Hint [generate] succeeds with.
  String hint = 'Plan the day #Work @planning 09:00';

  /// When non-null, [generate] throws it instead of returning [hint].
  Object? generateError;

  final generateCalls = <({List<String> recentTaskTitles, String locale})>[];

  @override
  Future<String> generate({
    required List<String> recentTaskTitles,
    required String locale,
  }) async {
    generateCalls.add((recentTaskTitles: recentTaskTitles, locale: locale));
    final error = generateError;
    if (error != null) throw error;
    return hint;
  }
}
