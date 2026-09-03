import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap creates only the master template', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-env-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/.env.example').writeAsString('''
LOCAL__POMODOIST_ENVIRONMENT=local
PRIVATE__ASC_KEY_ID=
''');

    final result = await _run('bootstrap', ['--root', root.path]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      File('${root.path}/.env.setup').readAsStringSync(),
      contains('LOCAL__POMODOIST_ENVIRONMENT=local'),
    );
    expect(File('${root.path}/.env.local').existsSync(), isFalse);
    expect(File('${root.path}/.env.private').existsSync(), isFalse);
  });

  test('bootstrap leaves an existing master untouched', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-env-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/.env.example').writeAsString('''
LOCAL__EXISTING=template
LOCAL__ADDED=default
''');
    await File(
      '${root.path}/.env.setup',
    ).writeAsString('LOCAL__EXISTING=private-value\n');

    final result = await _run('bootstrap', ['--root', root.path]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(_values('${root.path}/.env.setup'), {
      'LOCAL__EXISTING': 'private-value',
    });
  });

  test('filled master values sync into already generated files', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-env-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/.env.example').writeAsString('''
LOCAL__POMODOIST_ENVIRONMENT=local
LOCAL__SUPABASE_URL=
''');

    final bootstrapped = await _run('bootstrap', ['--root', root.path]);
    expect(bootstrapped.exitCode, 0, reason: bootstrapped.stderr.toString());
    final first = await _run('sync', ['--root', root.path]);
    expect(first.exitCode, 0, reason: first.stderr.toString());
    expect(_values('${root.path}/.env.local'), {
      'POMODOIST_ENVIRONMENT': 'local',
      'SUPABASE_URL': '',
    });

    await File('${root.path}/.env.setup').writeAsString('''
LOCAL__POMODOIST_ENVIRONMENT=
LOCAL__SUPABASE_URL=https://real.supabase.co
''');

    final second = await _run('sync', ['--root', root.path]);
    expect(second.exitCode, 0, reason: second.stderr.toString());
    expect(_values('${root.path}/.env.local'), {
      'POMODOIST_ENVIRONMENT': 'local',
      'SUPABASE_URL': 'https://real.supabase.co',
    });
  });

  test('sync distributes profiles and syncs non-empty master values', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-env-');
    addTearDown(() => root.delete(recursive: true));
    const template = '''
LOCAL__POMODOIST_ENVIRONMENT=local
LOCAL__NEW_VALUE=
STAGING__POMODOIST_ENVIRONMENT=staging
TESTFLIGHT__POMODOIST_ENVIRONMENT=production
WINDOWS__POMODOIST_ENVIRONMENT=production
LINUX__POMODOIST_ENVIRONMENT=production
PRIVATE__ASC_KEY_ID=
''';
    await File('${root.path}/.env.example').writeAsString(template);
    await File('${root.path}/.env.setup').writeAsString('''
LOCAL__POMODOIST_ENVIRONMENT=local-from-master
LOCAL__NEW_VALUE=added
STAGING__POMODOIST_ENVIRONMENT=staging
TESTFLIGHT__POMODOIST_ENVIRONMENT=production
WINDOWS__POMODOIST_ENVIRONMENT=production
LINUX__POMODOIST_ENVIRONMENT=production
PRIVATE__ASC_KEY_ID=ABC1234567
''');
    await File(
      '${root.path}/.env.local',
    ).writeAsString('POMODOIST_ENVIRONMENT=manual-local\n');

    final result = await _run('sync', ['--root', root.path]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(_values('${root.path}/.env.local'), {
      'POMODOIST_ENVIRONMENT': 'local-from-master',
      'NEW_VALUE': 'added',
    });
    expect(
      _values('${root.path}/.env.staging')['POMODOIST_ENVIRONMENT'],
      'staging',
    );
    expect(
      _values('${root.path}/.env.testflight')['POMODOIST_ENVIRONMENT'],
      'production',
    );
    expect(
      _values('${root.path}/.env.windows')['POMODOIST_ENVIRONMENT'],
      'production',
    );
    expect(
      _values('${root.path}/.env.linux')['POMODOIST_ENVIRONMENT'],
      'production',
    );
    expect(_values('${root.path}/.env.private')['ASC_KEY_ID'], 'ABC1234567');
  });

  test('sync adds new master keys without replacing existing values', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-env-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/.env.example').writeAsString('''
LOCAL__EXISTING=template
LOCAL__ADDED=default
''');
    await File(
      '${root.path}/.env.setup',
    ).writeAsString('LOCAL__EXISTING=private-value\n');

    final result = await _run('sync', ['--root', root.path]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(_values('${root.path}/.env.setup'), {
      'LOCAL__EXISTING': 'private-value',
      'LOCAL__ADDED': 'default',
    });
  });

  test('malformed input fails without echoing its value', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-env-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/.env.example').writeAsString('LOCAL__TOKEN=\n');
    await File('${root.path}/.env.setup').writeAsString('''
LOCAL__TOKEN=first-private-value
LOCAL__TOKEN=second-private-value
''');

    final result = await _run('sync', ['--root', root.path]);
    final error = result.stderr.toString();

    expect(result.exitCode, 64);
    expect(error, contains('LOCAL__TOKEN'));
    expect(error, isNot(contains('first-private-value')));
    expect(error, isNot(contains('second-private-value')));
  });

  test('Apple private key is decoded into a mode-600 temporary file', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('pomodoist-env-');
    addTearDown(() => root.delete(recursive: true));
    const key =
        '-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----\n';
    final privateEnv = File('${root.path}/.env.private');
    await privateEnv.writeAsString(
      'ASC_PRIVATE_KEY_BASE64=${base64Encode(utf8.encode(key))}\n',
    );
    final output = '${root.path}/AuthKey_TEST.p8';

    final result = await _run('write-asc-key', [
      '--env',
      privateEnv.path,
      '--output',
      output,
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(File(output).readAsStringSync(), key);
    expect(File(output).statSync().mode & 0x1ff, 0x180);
  });

  test('staging preflight names the missing Apple private key', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-env-');
    addTearDown(() => root.delete(recursive: true));
    final privateEnv = File('${root.path}/.env.private');
    await privateEnv.writeAsString('''
APPLE_TEAM_ID=team-value-must-not-leak
APPLE_PRIVATE_KEY_BASE64=
''');

    final result = await _run('validate-staging', ['--env', privateEnv.path]);

    expect(result.exitCode, 64);
    expect(result.stderr.toString(), contains('APPLE_PRIVATE_KEY_BASE64'));
    expect(
      result.stderr.toString(),
      isNot(contains('team-value-must-not-leak')),
    );
  });
}

Future<ProcessResult> _run(String command, List<String> arguments) {
  return Process.run(_dartExecutable(), [
    'tool/env_setup.dart',
    command,
    ...arguments,
  ], workingDirectory: Directory.current.path);
}

Map<String, String> _values(String path) {
  final result = <String, String>{};
  for (final line in File(path).readAsLinesSync()) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final separator = line.indexOf('=');
    result[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return result;
}

String _dartExecutable() {
  final pinned = File('.fvm/flutter_sdk/bin/dart');
  return pinned.existsSync() ? pinned.absolute.path : 'dart';
}
