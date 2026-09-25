import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const desktopWorkflows = {
    '../../.github/workflows/linux-appimage-release.yml': 'build-test-publish',
    '../../.github/workflows/windows-exe-preview.yml': 'build-test',
  };
  for (final entry in desktopWorkflows.entries) {
    test('${entry.key} prepares stable and RC versions before pub get', () {
      final steps = _job(entry.key, entry.value)['steps'] as YamlList;
      final versionIndex = steps.indexWhere(
        (step) => step['name'] == 'Prepare application version',
      );
      expect(versionIndex, greaterThanOrEqualTo(0));
      final pubGetIndex = steps.indexWhere(
        (step) => _resolvesDependencies(step['run'] as String? ?? ''),
      );
      expect(pubGetIndex, greaterThanOrEqualTo(0));
      expect(versionIndex, lessThan(pubGetIndex));
      // The Flutter build and .dart_tool paths are symlinks into the ignored
      // repository-root build directory, so a fresh checkout has to recreate
      // them before pub get; make linux-pub-get and the Windows entry scripts
      // both link first.
      final linkIndex = steps.indexWhere(
        (step) => _linksFlutterBuild(step),
      );
      expect(
        linkIndex,
        inInclusiveRange(0, pubGetIndex),
        reason: 'link step not before pub get in ${entry.key}: $steps',
      );
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
          final pubspec = File('${temp.path}/apps/flutter/pubspec.yaml')
            ..createSync(recursive: true)
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
          final pubspec = File('${temp.path}/apps/flutter/pubspec.yaml')
            ..createSync(recursive: true)
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

  test('tag publication waits for every platform and preserves RC status', () {
    final publishers = [
      (
        path: '../../.github/workflows/linux-appimage-release.yml',
        job: 'build-test-publish',
        step: 'Upload AppImage and publish complete desktop release',
        assets: [
          'Pomodoist-x86_64.AppImage',
          'Pomodoist-x86_64.AppImage.sha256',
        ],
        legacyGh: 'true',
      ),
      (
        path: '../../.github/workflows/windows-exe-preview.yml',
        job: 'publish',
        step: 'Upload EXE and publish complete desktop release',
        assets: ['Pomodoist-Setup.exe', 'Pomodoist-Setup.exe.sha256'],
        legacyGh: 'false',
      ),
      (
        path: '../../.github/workflows/macos-dmg-release.yml',
        job: 'publish',
        step: 'Upload DMG and publish complete desktop release',
        assets: ['Pomodoist-macOS.dmg', 'Pomodoist-macOS.dmg.sha256'],
        legacyGh: 'false',
      ),
      (
        path: '../../.github/workflows/android-release.yml',
        job: 'signed-apk-and-bundle',
        step: 'Publish Android artifacts to the GitHub release',
        assets: ['Pomodoist-Android.apk', 'Pomodoist-Android.apk.sha256'],
        legacyGh: 'false',
      ),
    ];
    final scripts = <String>[];
    for (final publisher in publishers) {
      final job = _job(publisher.path, publisher.job);
      final step = (job['steps'] as YamlList).cast<YamlMap>().singleWhere(
        (step) => step['name'] == publisher.step,
      );
      expect(
        (step['env'] as YamlMap?)?['GH_REPO'] ??
            (job['env'] as YamlMap?)?['GH_REPO'],
        r'${{ github.repository }}',
        reason: publisher.path,
      );
      scripts.add(step['run'] as String);
    }

    for (final tag in ['v1.0.3', 'v1.0.3-rc.1']) {
      for (final order in [
        [0, 1, 2, 3],
        [1, 2, 3, 0],
        [3, 2, 1, 0],
      ]) {
        final temp = Directory.systemTemp.createTempSync('release-publish-');
        try {
          final prerelease = tag.contains('-rc.');
          final environment = {
            'GITHUB_REF_NAME': tag,
            'GITHUB_REPOSITORY': 'example/pomodoist',
            'GH_REPO': 'example/pomodoist',
            'GITHUB_SHA': '0123456789abcdef0123456789abcdef01234567',
          };
          ProcessResult publish(int position) {
            final publisher = publishers[order[position]];
            return _bash('$_fakeGh\n${scripts[order[position]]}', temp, {
              ...environment,
              'LEGACY_GH': publisher.legacyGh,
            });
          }

          // Three platforms are never enough, and a repeated platform stays idempotent.
          for (final position in [0, 1, 2, 0]) {
            final publisher = publishers[order[position]];
            final result = publish(position);
            expect(result.exitCode, 0, reason: '${result.stderr}');
            expect(
              result.stdout,
              contains(
                'Release remains draft until all release assets are present.',
              ),
              reason: publisher.path,
            );
            expect(
              File('${temp.path}/gh.log').readAsStringSync(),
              isNot(contains('--method PATCH')),
              reason: publisher.path,
            );
            expect(
              File('${temp.path}/assets').readAsLinesSync(),
              containsAll(publisher.assets),
              reason: publisher.path,
            );
          }

          final last = publish(3);
          expect(last.exitCode, 0, reason: '${last.stderr}');
          final log = File('${temp.path}/gh.log').readAsLinesSync();
          final publication = log.singleWhere(
            (line) => line.startsWith('api --method PATCH'),
          );
          expect(publication, contains('--raw-field tag_name=$tag'));
          expect(publication, contains('--field draft=false'));
          expect(publication, contains('--field prerelease=$prerelease'));
          expect(
            publication,
            contains('--raw-field make_latest=${!prerelease}'),
          );
          expect(
            log.where(
              (line) =>
                  line.startsWith('release create ') ||
                  line.startsWith(
                    'api --method POST repos/example/pomodoist/releases ',
                  ),
            ),
            hasLength(1),
          );
          expect(log.where((line) => line == 'generate-notes'), hasLength(1));
          expect(File('${temp.path}/assets').readAsLinesSync().toSet(), {
            for (final publisher in publishers) ...publisher.assets,
          });
        } finally {
          temp.deleteSync(recursive: true);
        }
      }
    }
  });

  test('Linux reuses a draft created during a concurrent publish', () {
    final steps = _job(
      '../../.github/workflows/linux-appimage-release.yml',
      'build-test-publish',
    )['steps'] as YamlList;
    final script = (steps.cast<YamlMap>().singleWhere(
      (step) =>
          step['name'] == 'Upload AppImage and publish complete desktop release',
    ))['run'] as String;
    final temp = Directory.systemTemp.createTempSync('release-race-');
    try {
      final result = _bash('$_fakeGh\n$script', temp, {
        'GITHUB_REF_NAME': 'v1.0.3-rc.1',
        'GITHUB_REPOSITORY': 'example/pomodoist',
        'GH_REPO': 'example/pomodoist',
        'GITHUB_SHA': '0123456789abcdef0123456789abcdef01234567',
        'CREATE_RACE': 'true',
      });
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${temp.path}/assets').readAsLinesSync(), [
        'Pomodoist-x86_64.AppImage',
        'Pomodoist-x86_64.AppImage.sha256',
      ]);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('Linux trusts the resolved SDK and checkout before running Flutter', () {
    final steps =
        _job(
              '../../.github/workflows/linux-appimage-release.yml',
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
          (step) => _resolvesDependencies(step['run'] as String? ?? ''),
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
    '../../.github/workflows/android-release.yml',
    '../../.github/workflows/linux-appimage-release.yml',
    '../../.github/workflows/macos-dmg-release.yml',
    '../../.github/workflows/validate.yml',
    '../../.github/workflows/windows-exe-preview.yml',
  ]) {
    test('$path is valid YAML', () {
      final document = loadYaml(File(path).readAsStringSync());

      expect(document, isA<YamlMap>());
      expect((document as YamlMap)['jobs'], isA<YamlMap>());
    });
  }

  test('desktop builders have independent queues for the same tag', () {
    final workflows = [
      '../../.github/workflows/linux-appimage-release.yml',
      '../../.github/workflows/windows-exe-preview.yml',
      '../../.github/workflows/macos-dmg-release.yml',
    ];
    for (final path in workflows) {
      final workflow = loadYaml(File(path).readAsStringSync()) as YamlMap;
      final group = (workflow['concurrency'] as YamlMap)['group'] as String;
      expect(
        group,
        r'desktop-release-${{ github.workflow }}-${{ github.ref }}',
        reason: path,
      );
    }
  });

  test('one tag release waits for Linux, Windows, macOS and Android assets', () {
    for (final path in [
      '../../.github/workflows/linux-appimage-release.yml',
      '../../.github/workflows/windows-exe-preview.yml',
      '../../.github/workflows/macos-dmg-release.yml',
    ]) {
      final workflow = File(path).readAsStringSync();
      expect(workflow, contains("- 'v*.*.*'"), reason: path);
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
      expect(workflow, contains('Pomodoist-macOS.dmg'), reason: path);
      expect(workflow, contains('Pomodoist-macOS.dmg.sha256'), reason: path);
      expect(workflow, contains('Pomodoist-Android.apk'), reason: path);
      expect(workflow, contains('Pomodoist-Android.apk.sha256'), reason: path);
      expect(
        workflow,
        contains('Release remains draft until all release assets are present.'),
        reason: path,
      );
    }
  });

  test('desktop release workflows do not depend on SignPath', () {
    for (final path in [
      '../../.github/workflows/linux-appimage-release.yml',
      '../../.github/workflows/windows-exe-preview.yml',
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
      '../../.github/workflows/linux-appimage-release.yml',
    ).readAsStringSync();
    final windows = File(
      '../../.github/workflows/windows-exe-preview.yml',
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
                '../../.github/workflows/linux-appimage-release.yml',
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
                '../../.github/workflows/windows-exe-preview.yml',
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
    expect(publish['environment'], 'windows-production');
    expect((publish['permissions'] as YamlMap)['contents'], 'write');
  });

  test('Android release publishes signed artifacts and gates the tag', () {
    final document =
        loadYaml(
              File(
                '../../.github/workflows/android-release.yml',
              ).readAsStringSync(),
            )
            as YamlMap;
    expect((document['permissions'] as YamlMap)['contents'], 'read');
    expect(
      (document['concurrency'] as YamlMap)['group'],
      r'android-release-${{ github.ref }}',
    );

    final jobs = document['jobs'] as YamlMap;
    final job = jobs['signed-apk-and-bundle'] as YamlMap;
    expect((job['permissions'] as YamlMap)['contents'], 'write');

    final publish = (job['steps'] as YamlList).cast<YamlMap>().singleWhere(
      (step) =>
          step['name'] == 'Publish Android artifacts to the GitHub release',
    );
    expect(publish['if'], "github.ref_type == 'tag'");

    final script = publish['run'] as String;
    for (final asset in <String>[
      'Pomodoist-Android.apk',
      'Pomodoist-Android.apk.sha256',
    ]) {
      expect(script, contains(asset));
    }
    expect(script, isNot(contains('Pomodoist-Android.aab')));
    expect(script, contains('gh release upload'));
    expect(script, contains('--clobber'));
    expect(script, contains('required_assets=('));
    expect(script, contains('Pomodoist-macOS.dmg'));

    final bundle = (job['steps'] as YamlList).cast<YamlMap>().singleWhere(
      (step) => step['name'] == 'Save signed release artifacts',
    );
    final artifact = bundle['with'] as YamlMap;
    expect(artifact['name'], r'pomodoist-android-${{ github.sha }}');
    expect(artifact['path'], 'build/flutter/android/release/');
    expect(artifact['retention-days'], 90);
  });

  test('Windows production builds configure native CAPTCHA', () {
    for (final path in ['../../.github/workflows/windows-exe-preview.yml']) {
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

/// Matches every step that resolves Dart dependencies, whether it calls
/// Flutter directly or goes through a Make target that wraps pub get.
bool _resolvesDependencies(String run) =>
    run.contains('flutter pub get') ||
    run.contains('linux-pub-get') ||
    run.contains('pub_get_with_retry');

/// The Flutter project keeps build/ and .dart_tool as symlinks into the
/// ignored repository-root build directory, so every entry point has to
/// recreate them before Flutter runs.
bool _linksFlutterBuild(YamlMap step) {
  final run = step['run'] as String? ?? '';
  if (run.contains('flutter-build-link') ||
      run.contains('linux-pub-get') ||
      run.contains('link-build.sh')) {
    return true;
  }
  final uses = step['uses'] as String? ?? '';
  if (uses.contains('link-build.ps1')) {
    return true;
  }
  // The Windows workflow runs its linking script through `shell: powershell`.
  return run.contains('link-build.ps1');
}

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

// Execute the real publication scripts; generation is tested in Python.
const _fakeGh = r'''
python3() {
  echo generate-notes >> gh.log
  echo 'Generated release notes'
}
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
        [[ "${CREATE_RACE:-false}" != true ]] || return 22
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
