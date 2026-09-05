import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const desktopWorkflows = {
    '.github/workflows/linux-appimage-release.yml': 'build-test-publish',
    '.github/workflows/windows-exe-preview.yml': 'build-test',
  };
  for (final entry in desktopWorkflows.entries) {
    test('${entry.key} prepares stable and RC versions before pub get', () {
      final steps = _job(entry.key, entry.value)['steps'] as YamlList;
      final versionIndex = steps.indexWhere(
        (step) => step['name'] == 'Prepare application version',
      );
      expect(versionIndex, greaterThanOrEqualTo(0));
      final pubGetIndex = steps.indexWhere(
        (step) => (step['run'] as String? ?? '').contains('flutter pub get'),
      );
      expect(versionIndex, lessThan(pubGetIndex));
      final script = steps[versionIndex]['run'] as String;
      for (final (tag, newline) in [
        ('v1.0.3', '\n'),
        ('v1.0.3-rc.1', '\n'),
        ('main', '\n'),
        ('v1.0.3-rc.1', '\r\n'),
        ('main', '\r\n'),
      ]) {
        final temp = Directory.systemTemp.createTempSync('desktop-version-');
        try {
          final pubspec = File('${temp.path}/pubspec.yaml')
            ..writeAsStringSync(
              'name: pomodoist${newline}version: 0.9.0+91$newline',
            );
          final result = _bash(script, temp, {
            'GITHUB_REF_TYPE': tag == 'main' ? 'branch' : 'tag',
            'GITHUB_REF_NAME': tag,
          });
          expect(result.exitCode, 0, reason: '${result.stderr}');
          final expected = tag == 'main' ? '0.9.0' : tag.substring(1);
          final expectedNewline = tag == 'main' ? newline : '\n';
          expect(
            pubspec.readAsStringSync(),
            'name: pomodoist${expectedNewline}version: $expected+91$expectedNewline',
          );
          expect(
            File('${temp.path}/env').readAsLinesSync(),
            contains('POMODOIST_VERSION=$expected'),
          );
          expect(
            File('${temp.path}/output').readAsLinesSync(),
            contains('version=$expected'),
          );
        } finally {
          temp.deleteSync(recursive: true);
        }
      }
      for (final tag in [
        '1.0.3',
        'v1.0',
        'v1.0.3-beta.1',
        'v1.0.3-rc.',
        'v1.0.3-rc.01',
        'v01.0.3',
        'v1.0.3+4',
        'v1.0.3-rc.1/extra',
      ]) {
        final temp = Directory.systemTemp.createTempSync('desktop-invalid-');
        try {
          final pubspec = File('${temp.path}/pubspec.yaml')
            ..writeAsStringSync('version: 0.9.0+91\n');
          final result = _bash(script, temp, {
            'GITHUB_REF_TYPE': 'tag',
            'GITHUB_REF_NAME': tag,
          });
          expect(result.exitCode, isNot(0), reason: tag);
          expect(pubspec.readAsStringSync(), 'version: 0.9.0+91\n');
        } finally {
          temp.deleteSync(recursive: true);
        }
      }
    });
  }

  test('tag publication waits for both platforms and preserves RC status', () {
    for (final tag in ['v1.0.3', 'v1.0.3-rc.1']) {
      final temp = Directory.systemTemp.createTempSync('desktop-publish-');
      try {
        final scripts = <String>[];
        for (final entry in desktopWorkflows.entries) {
          final job = _job(
            entry.key,
            entry.value == 'build-test' ? 'publish' : entry.value,
          );
          final steps = job['steps'] as YamlList;
          final step = steps.cast<YamlMap>().singleWhere(
            (step) => (step['name'] as String? ?? '').contains(
              'publish complete desktop release',
            ),
          );
          expect(
            (job['env'] as YamlMap)['GH_REPO'],
            r'${{ github.repository }}',
          );
          scripts.add(step['run'] as String);
        }
        final environment = {
          'GITHUB_REF_NAME': tag,
          'GITHUB_REPOSITORY': 'example/pomodoist',
          'GH_REPO': 'example/pomodoist',
          'GITHUB_SHA': '0123456789abcdef0123456789abcdef01234567',
        };
        final first = _bash('$_fakeGh\n${scripts[0]}', temp, {
          ...environment,
          'LEGACY_GH': 'true',
        });
        expect(first.exitCode, 0, reason: '${first.stderr}');
        final log = File('${temp.path}/gh.log');
        expect(log.readAsStringSync(), isNot(contains('--method PATCH')));
        final prerelease = tag.contains('-rc.');
        expect(
          log.readAsStringSync(),
          contains('--field prerelease=$prerelease'),
        );
        final second = _bash('$_fakeGh\n${scripts[1]}', temp, environment);
        expect(second.exitCode, 0, reason: '${second.stderr}');
        final publication = log.readAsLinesSync().singleWhere(
          (line) => line.startsWith('api --method PATCH'),
        );
        expect(publication, contains('--field prerelease=$prerelease'));
        expect(publication, contains('--raw-field make_latest=${!prerelease}'));
        expect(publication, contains('--field draft=false'));
        expect(publication, contains('--raw-field tag_name=$tag'));
        final retry = _bash('$_fakeGh\n${scripts[0]}', temp, {
          ...environment,
          'LEGACY_GH': 'true',
        });
        expect(retry.exitCode, 0, reason: '${retry.stderr}');
        expect(
          log.readAsLinesSync().where(
            (line) => line.startsWith(
              'api --method POST repos/example/pomodoist/releases ',
            ),
          ),
          hasLength(1),
        );
        expect(File('${temp.path}/assets').readAsLinesSync().toSet(), {
          'Pomodoist-x86_64.AppImage',
          'Pomodoist-x86_64.AppImage.sha256',
          'Pomodoist-Setup.exe',
          'Pomodoist-Setup.exe.sha256',
        });
      } finally {
        temp.deleteSync(recursive: true);
      }
    }
  });

  test('Linux trusts the resolved SDK and checkout before running Flutter', () {
    final steps =
        _job(
              '.github/workflows/linux-appimage-release.yml',
              'build-test-publish',
            )['steps']
            as YamlList;
    final trustIndex = steps.indexWhere(
      (step) =>
          step['name'] ==
          'Trust Flutter SDK and checkout in the Linux container',
    );
    expect(
      trustIndex,
      greaterThan(
        steps.indexWhere(
          (step) => (step['uses'] as String? ?? '').startsWith(
            'subosito/flutter-action@',
          ),
        ),
      ),
    );
    expect(
      trustIndex,
      lessThan(
        steps.indexWhere(
          (step) => (step['run'] as String? ?? '').contains('flutter pub get'),
        ),
      ),
    );
    final temp = Directory.systemTemp.createTempSync('flutter-sdk-');
    try {
      final sdk = Directory('${temp.path}/sdk with spaces')..createSync();
      Directory('${sdk.path}/bin').createSync();
      final flutter = File('${sdk.path}/bin/flutter')
        ..writeAsStringSync('#!/bin/sh\nexit 0\n');
      Process.runSync('chmod', ['+x', flutter.path]);
      final bin = Directory('${temp.path}/bin')..createSync();
      Link('${bin.path}/flutter').createSync(flutter.path);
      final config = '${temp.path}/gitconfig';
      final result = _bash(steps[trustIndex]['run'] as String, temp, {
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
        'GIT_CONFIG_GLOBAL': config,
        'GITHUB_WORKSPACE': temp.path,
      });
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final trusted = Process.runSync('git', [
        'config',
        '--file',
        config,
        '--get-all',
        'safe.directory',
      ]);
      expect(trusted.stdout.toString().trim().split('\n'), [
        sdk.resolveSymbolicLinksSync(),
        temp.path,
      ]);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  for (final path in [
    '.github/workflows/linux-appimage-release.yml',
    '.github/workflows/validate.yml',
    '.github/workflows/windows-exe-preview.yml',
  ]) {
    test('$path is valid YAML', () {
      final document = loadYaml(File(path).readAsStringSync());

      expect(document, isA<YamlMap>());
      expect((document as YamlMap)['jobs'], isA<YamlMap>());
    });
  }

  test('one tag release waits for Linux AppImage and Windows EXE assets', () {
    for (final path in [
      '.github/workflows/linux-appimage-release.yml',
      '.github/workflows/windows-exe-preview.yml',
    ]) {
      final workflow = File(path).readAsStringSync();
      expect(workflow, contains("- 'v*.*.*'"), reason: path);
      expect(
        workflow,
        contains(r'group: desktop-release-${{ github.ref }}'),
        reason: path,
      );
      expect(
        workflow,
        anyOf(contains('--draft'), contains('--field draft=true')),
        reason: path,
      );
      expect(workflow, contains('required_assets=('), reason: path);
      expect(workflow, contains('Pomodoist-x86_64.AppImage'), reason: path);
      expect(
        workflow,
        contains('Pomodoist-x86_64.AppImage.sha256'),
        reason: path,
      );
      expect(workflow, contains('Pomodoist-Setup.exe'), reason: path);
      expect(workflow, contains('Pomodoist-Setup.exe.sha256'), reason: path);
      expect(
        workflow,
        contains('Release remains draft until all desktop assets are present.'),
        reason: path,
      );
    }
  });

  test('desktop release workflows do not depend on SignPath', () {
    for (final path in [
      '.github/workflows/linux-appimage-release.yml',
      '.github/workflows/windows-exe-preview.yml',
    ]) {
      expect(
        File(path).readAsStringSync().toLowerCase(),
        isNot(contains('signpath')),
        reason: path,
      );
    }
  });

  test('desktop workflows verify artifacts without launching them', () {
    final linux = File(
      '.github/workflows/linux-appimage-release.yml',
    ).readAsStringSync();
    final windows = File(
      '.github/workflows/windows-exe-preview.yml',
    ).readAsStringSync();
    expect(linux, contains('sha256sum --check'));
    expect(linux, isNot(contains('--appimage-extract')));
    expect(linux, isNot(contains('APP_RUN')));
    expect(windows, contains('Get-FileHash'));
    expect(windows, contains('FileVersionInfo'));
    expect(windows, isNot(contains('smoke.ps1')));
  });

  test('Linux CI uses the validated local AppImage build contract', () {
    final document =
        loadYaml(
              File(
                '.github/workflows/linux-appimage-release.yml',
              ).readAsStringSync(),
            )
            as YamlMap;
    final jobs = document['jobs'] as YamlMap;
    final build = jobs['build-test-publish'] as YamlMap;
    final steps = build['steps'] as YamlList;
    final buildStep = steps.cast<YamlMap>().singleWhere(
      (step) => step['name'] == 'Build production AppImage',
    );
    final command = buildStep['run'] as String;

    expect(command, contains('make linux-appimage'));
    expect(
      command,
      contains('LINUX_CONFIG="\$RUNNER_TEMP/linux-production.json"'),
    );
    expect(command, contains('POMODOIST_RELEASE="\$GITHUB_SHA"'));
  });

  test('Windows EXE build isolates production build from publishing', () {
    final document =
        loadYaml(
              File(
                '.github/workflows/windows-exe-preview.yml',
              ).readAsStringSync(),
            )
            as YamlMap;
    final jobs = document['jobs'] as YamlMap;

    expect(
      jobs.keys,
      containsAll(<String>['validate-ref', 'build-test', 'publish']),
    );

    final validateRef = jobs['validate-ref'] as YamlMap;
    expect((validateRef['permissions'] as YamlMap)['contents'], 'read');

    final build = jobs['build-test'] as YamlMap;
    expect(build['needs'], 'validate-ref');
    expect(build['environment'], 'windows-production');
    expect((build['permissions'] as YamlMap)['contents'], 'read');
    expect(build.containsKey('env'), isFalse);

    final buildSteps = build['steps'] as YamlList;
    final installInnoStep = buildSteps.cast<YamlMap>().singleWhere(
      (step) => step['name'] == 'Install Inno Setup 6.7.1',
    );
    final installInnoScript = installInnoStep['run'] as String;
    expect(installInnoScript, isNot(contains('VersionInfo.ProductVersion')));
    expect(installInnoScript, contains('Get-FileHash'));
    expect(
      installInnoScript,
      contains(
        'EB6F4410C8DB367A5F74127E8025AD2CCACC0AFABBE783959D237DF3050F97FB',
      ),
    );

    final publish = jobs['publish'] as YamlMap;
    expect(publish['needs'], 'build-test');
    expect(publish.containsKey('environment'), isFalse);
    expect((publish['permissions'] as YamlMap)['contents'], 'write');
  });

  test('Windows production builds configure native CAPTCHA', () {
    for (final path in ['.github/workflows/windows-exe-preview.yml']) {
      final workflow = File(path).readAsStringSync();
      expect(
        workflow,
        contains(
          "POMODOIST_REGISTRATION_URL = 'https://app.pomodoist.com/auth/challenge'",
        ),
        reason: path,
      );
    }
  });
}

YamlMap _job(String path, String name) =>
    (loadYaml(File(path).readAsStringSync())['jobs'] as YamlMap)[name]
        as YamlMap;

ProcessResult _bash(
  String script,
  Directory directory,
  Map<String, String> env,
) => Process.runSync(
  'bash',
  ['-euo', 'pipefail', '-c', script],
  workingDirectory: directory.path,
  environment: {
    ...env,
    'GITHUB_ENV': '${directory.path}/env',
    'GITHUB_OUTPUT': '${directory.path}/output',
  },
);

// Replace only the GitHub network boundary; execute the real workflow scripts.
const _fakeGh = r'''
gh() {
  [[ "$GH_REPO" == example/pomodoist ]] || return 128
  printf '%s\n' "$*" >> gh.log
  case "$1 $2" in
    'release view') [[ -f release-exists ]] ;;
    'release create') touch release-exists ;;
    'release upload')
      [[ "${LEGACY_GH:-false}" != true ]] || return 22
      shift 3
      for asset in "$@"; do
        [[ "$asset" == --clobber ]] || basename "$asset" >> assets
      done
      ;;
    'api --method')
      if [[ "$3" == POST && "$4" == */releases ]]; then
        touch release-exists
        echo 123
      elif [[ "$3" == POST && "$4" == https://uploads.github.com/* ]]; then
        echo "${4##*name=}" >> assets
      elif [[ "$3" == DELETE ]]; then
        sed -i.bak "/^${4##*/}$/d" assets
      fi
      ;;
    api*)
      # GitHub's by-tag endpoint excludes draft releases.
      if [[ "$2" == */releases/tags/* ]]; then
        return 22
      elif [[ "$2" == */assets ]]; then
        if [[ "$*" == *'| .id'* ]]; then
          name=$(printf '%s' "${@: -1}" | sed -n 's/.*== "\(.*\)").*/\1/p')
          [[ ! -f assets ]] || grep -Fx "$name" assets || true
        else
          cat assets
        fi
      else
        [[ ! -f release-exists ]] || echo 123
      fi
      ;;
    *) return 64 ;;
  esac
}
''';
