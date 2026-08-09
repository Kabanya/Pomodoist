import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/planning/data/task_decomposer.dart';

void main() {
  test('Supabase decomposer sends local time and smart mode', () async {
    Map<String, Object?>? request;
    final decomposer = SupabaseTaskDecomposer(
      transport: (body) async {
        request = body;
        return {
          'ok': true,
          'tasks': [
            {
              'quickAdd': 'Подготовить отчет tomorrow 10:00',
              'description': 'Собрать цифры',
              'subtasks': [
                {'quickAdd': 'Экспортировать продажи'},
              ],
            },
          ],
        };
      },
    );

    final tasks = await decomposer.decompose(
      'подготовить отчет завтра утром',
      now: DateTime.parse('2026-07-13T12:00:00+03:00'),
      locale: 'ru-RU',
      smartMode: true,
    );

    expect(request, {
      'command': {
        'type': 'task.decomposeTranscript',
        'transcript': 'подготовить отчет завтра утром',
        'locale': 'ru-RU',
        'currentLocalTime': '2026-07-13T12:00:00.000+03:00',
        'smart': true,
      },
    });
    expect(tasks.single.description, 'Собрать цифры');
    expect(tasks.single.subtasks.single.quickAdd, 'Экспортировать продажи');
  });

  test('Supabase decomposer rejects a malformed success response', () async {
    final decomposer = SupabaseTaskDecomposer(
      transport: (_) async => {'ok': true, 'tasks': const []},
    );

    expect(
      () => decomposer.decompose(
        'купить молоко',
        now: DateTime.utc(2026, 7, 13),
        locale: 'ru-RU',
      ),
      throwsA(isA<TaskDecompositionException>()),
    );
  });
}
