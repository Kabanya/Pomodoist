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
    ], workingDirectory: _repoRoot);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final commands = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    expect(commands, hasLength(5));
    expect(
      commands[0],
      anyOf(
        contains('ln -s ../../build/flutter'),
        contains('link-build.ps1'),
      ),
      reason: 'the flutter build directory must resolve to the root build',
    );
    expect(
      commands[1],
      'cd "$_repoRoot/apps/flutter" && env -u http_proxy -u https_proxy -u all_proxy '
      '-u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY '
      'bash "$_repoRoot/tool/linux/pub_get_with_retry.sh" "flutter-under-test"',
    );
    expect(
      commands[2],
      'env -u http_proxy -u https_proxy -u all_proxy '
      '-u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY '
      '"dart-under-test" tool/desktop_release_config.dart '
      '--config "/secure config/pomodoist-linux-production.json"',
    );
    expect(
      commands[3],
      contains(
        'flutter-under-test" build linux --release '
        '--target "lib/main.dart" '
        '--dart-define-from-file="/secure config/'
        'pomodoist-linux-production.json" '
        '--dart-define=POMODOIST_RELEASE="0123456789abcdef0123456789abcdef01234567" '
        '--dart-define=POMODOIST_BILLING_CHANNEL=stripe',
      ),
    );
    expect(commands[3], isNot(contains('--no-pub')));
    expect(commands[4], contains('./tool/linux/build_appimage.sh'));
  });
}

String _makeExecutable() {
  final lookup = Process.runSync('which', const ['make']);
  if (lookup.exitCode != 0) {
    throw StateError('GNU Make is required for this test.');
  }
  return lookup.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
}

String get _repoRoot =>
    Directory('../..').resolveSymbolicLinksSync().replaceAll(r'\', '/');
