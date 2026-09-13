import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/task_detail_navigation.dart';

void main() {
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
}
