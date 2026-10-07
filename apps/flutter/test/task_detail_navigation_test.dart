import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';

void main() {
  test(
    'Calendar details retain the selected day when switching and closing',
    () {
      final background = Uri.parse('/calendar?date=2026-10-06');
      final opened = taskDetailUri(background, 'first');
      final switched = taskDetailUri(opened, 'second');
      expect(opened.queryParameters['date'], '2026-10-06');
      expect(switched.queryParameters['date'], '2026-10-06');
      expect(switched.queryParameters['task'], 'second');
      expect(taskDetailUri(switched, null), background);
    },
  );

  test('opening and closing details preserves the background query', () {
    final background = Uri.parse('/upcoming?date=2026-09-09&q=release#week');
    final opened = taskDetailUri(background, 'task / one');
    expect(opened.queryParameters['task'], 'task / one');
    expect(opened.queryParameters['date'], '2026-09-09');
    expect(opened.queryParameters['q'], 'release');
    expect(taskDetailUri(opened, null), background);
  });

  test('switching replaces the selected task without stacking parameters', () {
    final first = taskDetailUri(Uri.parse('/today'), 'one');
    final second = taskDetailUri(first, 'two');
    expect(second.queryParametersAll['task'], ['two']);
    expect(taskDetailUri(second, 'two'), second);
    expect(taskDetailUri(second, null).toString(), '/today');
  });

  test(
    'standalone details keep their canonical route when switching tasks',
    () {
      expect(taskDetailUri(Uri.parse('/task/old'), 'new id').pathSegments, [
        'task',
        'new id',
      ]);
      expect(taskDetailUri(Uri.parse('/task/old'), null).path, '/today');
    },
  );

  test('selected detail id comes from the panel or standalone route', () {
    expect(selectedTaskDetailsId(Uri.parse('/today?task=one')), 'one');
    expect(selectedTaskDetailsId(Uri.parse('/task/two')), 'two');
    expect(selectedTaskDetailsId(Uri.parse('/today')), isNull);
  });
}
