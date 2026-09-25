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
      anyOf(contains('ln -s ../../build/flutter'), contains('link-build.ps1')),
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
        '--flavor "production" '
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

  test('every Linux environment builds from its own profile and entry point', () {
    // The flavor, the entry point and the dotenv profile are one identity, so a
    // target that moves one without the others silently ships another
    // environment's build. The expected triple is spelled out per target rather
    // than derived from the same variables the Makefile uses, so a Makefile
    // change that moves all three together still fails here until it is
    // reviewed.
    const expected = <String, (String, String, String)>{
      'linux-debug-development': (
        'development',
        'lib/main_development.dart',
        'linux-dev.env',
      ),
      'linux-debug-staging': (
        'staging',
        'lib/main_staging.dart',
        'linux-stg.env',
      ),
      'linux-debug-production': ('production', 'lib/main.dart', 'linux.env'),
      'linux-profile-development': (
        'development',
        'lib/main_development.dart',
        'linux-dev.env',
      ),
      'linux-profile-staging': (
        'staging',
        'lib/main_staging.dart',
        'linux-stg.env',
      ),
      'linux-profile-production': ('production', 'lib/main.dart', 'linux.env'),
      'linux-release-development': (
        'development',
        'lib/main_development.dart',
        'linux-dev.env',
      ),
      'linux-release-staging': (
        'staging',
        'lib/main_staging.dart',
        'linux-stg.env',
      ),
      'linux-release-production': ('production', 'lib/main.dart', 'linux.env'),
    };

    for (final entry in expected.entries) {
      final (flavor, target, config) = entry.value;
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'DART=dart-under-test',
        'FLUTTER=flutter-under-test',
        'LINUX_CONFIG=linux.env',
        'LINUX_DEVELOPMENT_PROFILE=linux-dev.env',
        'LINUX_STAGING_PROFILE=linux-stg.env',
        'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
      ], workingDirectory: _repoRoot);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      final output = result.stdout.toString();
      expect(output, contains('--flavor "$flavor"'), reason: entry.key);
      expect(output, contains('--target "$target"'), reason: entry.key);
      expect(
        output,
        contains('--dart-define-from-file="$_repoRoot/$config"'),
        reason: entry.key,
      );
    }
  });

  test('Linux per-environment packaging consumes its own flavor bundle', () {
    // The bundle path carries the flavor segment, so packaging the production
    // path for a staging build would name one identity and ship another.
    const expected = <String, String>{
      'linux-appimage-development': 'development',
      'linux-appimage-staging': 'staging',
      'linux-appimage-production': 'production',
      'linux-install-development': 'development',
      'linux-install-staging': 'staging',
      'linux-install-production': 'production',
    };

    for (final entry in expected.entries) {
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'DART=dart-under-test',
        'FLUTTER=flutter-under-test',
        'LINUX_CONFIG=linux.env',
        'LINUX_DEVELOPMENT_PROFILE=linux-dev.env',
        'LINUX_STAGING_PROFILE=linux-stg.env',
        'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
      ], workingDirectory: _repoRoot);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      final output = result.stdout.toString();
      expect(
        output,
        contains(
          'POMODOIST_LINUX_BUNDLE="$_repoRoot/build/flutter/linux/x64/'
          '${entry.value}/release/bundle"',
        ),
        reason: entry.key,
      );
      expect(
        output,
        contains('--flavor "${entry.value}"'),
        reason: '${entry.key}: it must build the flavor it packages',
      );
    }
  });

  test('linux-debug is the development environment', () {
    final arguments = [
      '--no-print-directory',
      '--dry-run',
      'FLUTTER=flutter-under-test',
      'DART=dart-under-test',
      'LINUX_DEVELOPMENT_PROFILE=linux-dev.env',
      'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
    ];
    final bare = Process.runSync(_makeExecutable(), [
      ...arguments,
      'linux-debug',
    ], workingDirectory: _repoRoot);
    final explicit = Process.runSync(_makeExecutable(), [
      ...arguments,
      'linux-debug-development',
    ], workingDirectory: _repoRoot);

    expect(bare.exitCode, 0, reason: bare.stderr.toString());
    expect(explicit.exitCode, 0, reason: explicit.stderr.toString());
    expect(
      bare.stdout.toString(),
      explicit.stdout.toString(),
      reason: 'linux-debug must stay an alias of linux-debug-development',
    );
    expect(bare.stdout.toString(), contains('--flavor "development"'));
    expect(
      bare.stdout.toString(),
      contains('--target "lib/main_development.dart"'),
    );
  });

  test('linux-run follows the debug pair', () {
    final arguments = [
      '--no-print-directory',
      '--dry-run',
      'FLUTTER=flutter-under-test',
      'DART=dart-under-test',
      'LINUX_DEVELOPMENT_PROFILE=linux-dev.env',
      'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
    ];
    final run = Process.runSync(_makeExecutable(), [
      ...arguments,
      'linux-run',
    ], workingDirectory: _repoRoot);
    final debug = Process.runSync(_makeExecutable(), [
      ...arguments,
      'linux-debug',
    ], workingDirectory: _repoRoot);

    expect(run.exitCode, 0, reason: run.stderr.toString());
    final output = run.stdout.toString();
    expect(output, contains('"flutter-under-test" run -d linux --debug'));
    expect(output, contains('--flavor "development"'));
    expect(output, contains('--target "lib/main_development.dart"'));
    expect(
      output,
      contains('--dart-define-from-file="$_repoRoot/linux-dev.env"'),
    );
    expect(
      output,
      isNot(contains('build linux')),
      reason: 'linux-run runs the app instead of building a bundle',
    );
    for (final flag in [
      '--flavor "development"',
      '--target "lib/main_development.dart"',
    ]) {
      expect(
        debug.stdout.toString(),
        contains(flag),
        reason: 'linux-run and linux-debug must agree on $flag',
      );
    }
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
