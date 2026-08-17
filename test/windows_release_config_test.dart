import 'package:flutter_test/flutter_test.dart';

import '../tool/windows_release_config.dart';

void main() {
  test('maps the pubspec version and matching tag to an MSIX version', () {
    final version = WindowsReleaseVersion.fromPubspec(
      'name: pomodoist\nversion: 1.2.3+42\n',
      tag: 'v1.2.3',
      previousBuildNumber: 41,
    );

    expect(version.baseVersion, '1.2.3');
    expect(version.buildNumber, 42);
    expect(version.msixVersion, '1.2.3.42');
  });

  test('rejects a tag that does not match pubspec', () {
    expect(
      () => WindowsReleaseVersion.fromPubspec(
        'version: 1.2.3+42\n',
        tag: 'v1.2.4',
      ),
      throwsFormatException,
    );
  });

  test('rejects a non-increasing or out-of-range build number', () {
    expect(
      () => WindowsReleaseVersion.fromPubspec(
        'version: 1.2.3+42\n',
        tag: 'v1.2.3',
        previousBuildNumber: 42,
      ),
      throwsFormatException,
    );
    expect(
      () => WindowsReleaseVersion.fromPubspec(
        'version: 1.2.3+65536\n',
        tag: 'v1.2.3',
      ),
      throwsFormatException,
    );
  });

  test('builds a silent twelve-hour GitHub App Installer channel', () {
    final version = WindowsReleaseVersion.fromPubspec(
      'version: 1.2.3+42\n',
      tag: 'v1.2.3',
    );

    final xml = buildAppInstallerXml(
      version: version,
      publisher: 'CN=Finch & Forge',
      repository: 'Kabanya/Pomodoist',
    );

    expect(xml, contains('Version="1.2.3.42"'));
    expect(xml, contains('Name="com.finchforge.pomodoist"'));
    expect(xml, contains('Publisher="CN=Finch &amp; Forge"'));
    expect(
      xml,
      contains(
        'https://github.com/Kabanya/Pomodoist/releases/latest/download/'
        'Pomodoist.msixbundle',
      ),
    );
    expect(xml, contains('HoursBetweenUpdateChecks="12"'));
    expect(xml, isNot(contains('ShowPrompt')));
    expect(xml, isNot(contains('UpdateBlocksActivation')));
  });
}
