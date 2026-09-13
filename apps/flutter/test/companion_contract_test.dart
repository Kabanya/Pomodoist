import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/planning/data/task_decomposer.dart';

void main() {
  test('shared AI fixture preserves the command and editable result', () async {
    final fixtures =
        jsonDecode(
              File(
                '../../tool/tests/fixtures/companion_commands.json',
              ).readAsStringSync(),
            )
            as Map;
    final ai = fixtures['ai'] as Map;
    final request = (ai['request'] as Map).cast<String, Object?>();
    final command = (request['command'] as Map).cast<String, Object?>();
    Map<String, Object?>? sent;
    final decomposer = SupabaseTaskDecomposer(
      transport: (body) async {
        sent = body;
        return (ai['response'] as Map).cast<String, Object?>();
      },
    );
    final result = await decomposer.decompose(
      command['transcript'] as String,
      now: DateTime.parse(command['currentLocalTime'] as String),
      locale: command['locale'] as String,
      smartMode: command['smart'] as bool,
    );
    final sentCommand = (sent!['command'] as Map).cast<String, Object?>();
    expect(sentCommand, {...command, 'currentLocalTime': isA<String>()});
    expect(
      DateTime.parse(sentCommand['currentLocalTime'] as String),
      DateTime.parse(command['currentLocalTime'] as String),
    );
    expect(result.single.quickAdd, 'Buy milk');
    expect(result.single.subtasks, isEmpty);
  });
}
