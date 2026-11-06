import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/view_models/shell_view_model.dart';
import 'package:pomodoist/utils/clock.dart';

void main() {
  test('sidebar counts use the same injected day as planning screens', () {
    final queries = <TaskQuery>[];
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(FixedClock(DateTime(2040, 1, 2, 10))),
        accountProfileProvider.overrideWith((ref) => null),
        projectsProvider.overrideWith((ref) => Stream.value([])),
        tasksByQueryProvider.overrideWith((ref, query) {
          queries.add(query);
          return Stream.value([]);
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(shellSidebarViewModelProvider);
    expect(
      queries.where((q) => q.kind == TaskQueryKind.today).single.now,
      DateTime(2040, 1, 2),
    );
    expect(
      queries.where((q) => q.kind == TaskQueryKind.upcoming).single.now,
      DateTime(2040, 1, 2),
    );
  });
}
