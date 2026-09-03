import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux AppImage build resolves dependencies before validation', () {
    final result = Process.runSync(_makeExecutable(), const [
      '--no-print-directory',
      '--dry-run',
      'linux-appimage',
      'DART=dart-under-test',
      'FLUTTER=flutter-under-test',
      'LINUX_CONFIG=/secure config/pomodoist-linux-production.json',
      'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final commands = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    expect(commands, hasLength(4));
    expect(
      commands[0],
      'env -u http_proxy -u https_proxy -u all_proxy '
      '-u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY '
      'bash ./tool/linux/pub_get_with_retry.sh "flutter-under-test"',
    );
    expect(
      commands[1],
      'env -u http_proxy -u https_proxy -u all_proxy '
      '-u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY '
      'dart-under-test tool/desktop_release_config.dart '
      '--config "/secure config/pomodoist-linux-production.json"',
    );
    expect(
      commands[2],
      contains(
        'flutter-under-test build linux --release '
        '--dart-define-from-file="/secure config/'
        'pomodoist-linux-production.json" '
        '--dart-define=POMODOIST_RELEASE="0123456789abcdef0123456789abcdef01234567" '
        '--dart-define=POMODOIST_BILLING_CHANNEL=stripe',
      ),
    );
    expect(commands[2], isNot(contains('--no-pub')));
    expect(commands[3], contains('./tool/linux/build_appimage.sh'));
  });
}

String _makeExecutable() {
  final lookup = Process.runSync('which', const ['make']);
  if (lookup.exitCode != 0) {
    throw StateError('GNU Make is required for this test.');
  }
  return lookup.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
}
