import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
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
      expect(workflow, contains('--draft'), reason: path);
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

  test(
    'Linux release probes bundled audio and remote deep-link forwarding',
    () {
      final workflow = File(
        '.github/workflows/linux-appimage-release.yml',
      ).readAsStringSync();

      expect(workflow, contains('gst-launch-1.0'));
      expect(workflow, contains('focus_start.wav'));
      expect(workflow, contains('APP_RUN="\$appdir/AppRun"'));
      expect(workflow, contains('cold_start_log'));
      expect(workflow, contains('secondary_status'));
      expect(workflow, contains('Unhandled Exception'));
      expect(workflow, contains('POMODOIST_NATIVE_LINK_HANDLED'));
      expect(workflow, contains('test "\$secondary_status" -eq 0'));
      expect(workflow, contains('kill -0 "\$primary_pid"'));
    },
  );

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
