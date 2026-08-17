import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  for (final path in [
    '.github/workflows/validate.yml',
    '.github/workflows/windows-exe-preview.yml',
    '.github/workflows/windows-release.yml',
  ]) {
    test('$path is valid YAML', () {
      final document = loadYaml(File(path).readAsStringSync());

      expect(document, isA<YamlMap>());
      expect((document as YamlMap)['jobs'], isA<YamlMap>());
    });
  }

  test('Windows EXE preview isolates production build from publishing', () {
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
    for (final path in [
      '.github/workflows/windows-exe-preview.yml',
      '.github/workflows/windows-release.yml',
    ]) {
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
