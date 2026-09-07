import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/updates/update_release.dart';

Map<String, Object?> releaseFixture(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  String name = 'Pomodoist-x86_64.AppImage',
  bool checksum = true,
  String? digest,
  String? url,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'body': 'Release notes for $tag',
  'assets': [
    {
      'name': name,
      'size': 100,
      'state': 'uploaded',
      'digest': digest,
      'browser_download_url': url ??
          'https://github.com/Kabanya/Pomodoist/releases/download/$tag/$name',
    },
    if (checksum)
      {
        'name': '$name.sha256',
        'size': 100,
        'state': 'uploaded',
        'browser_download_url':
            'https://github.com/Kabanya/Pomodoist/releases/download/$tag/$name.sha256',
      },
  ],
};

const linuxTarget = UpdateTarget(UpdateOS.linux, UpdateArch.x64);

void main() {
  group('SemVer', () {
    test('compares numbers, RC identifiers and stable precedence', () {
      final versions = [
        '1.9.0', '1.10.0-rc.2', '1.10.0-rc.10', '1.10.0', '2.0.0',
      ].map(UpdateVersion.parse).toList();
      for (var i = 1; i < versions.length; i++) {
        expect(versions[i].compareTo(versions[i - 1]), greaterThan(0));
      }
    });
    test('build metadata is not precedence', () {
      expect(UpdateVersion.parse('v1.2.3+94').compareTo(
        UpdateVersion.parse('1.2.3+95')), 0);
    });
    for (final value in ['1.2', '01.2.3', '1.2.3-rc.01', '1.2.3-', 'latest', '1.2.3+']) {
      test('rejects malformed version $value', () {
        expect(UpdateVersion.tryParse(value), isNull);
      });
    }
  });

  UpdateOffer? select(List<Object?> releases, {
    UpdateChannel channel = UpdateChannel.stable,
    String current = '1.0.0',
    UpdateTarget target = linuxTarget,
  }) => selectUpdate(releases, current: UpdateVersion.parse(current),
    target: target, channel: channel);

  test('stable ignores drafts, flagged prereleases, alpha, beta and RC', () {
    expect(select([
      releaseFixture('v3.0.0', draft: true),
      releaseFixture('v2.8.0', prerelease: true),
      releaseFixture('v2.7.0-alpha.1'),
      releaseFixture('v2.6.0-beta.1'),
      releaseFixture('v2.5.0-rc.1'),
      releaseFixture('v2.0.0'),
    ])?.tag, 'v2.0.0');
  });
  test('RC includes RC and stable, never unrelated prereleases', () {
    expect(select([
      releaseFixture('v3.0.0-beta.1', prerelease: true),
      releaseFixture('v2.0.0-rc.2', prerelease: true),
      releaseFixture('v2.0.0-rc.10', prerelease: true),
    ], channel: UpdateChannel.rc)?.tag, 'v2.0.0-rc.10');
    expect(select([
      releaseFixture('v2.0.0'),
      releaseFixture('v2.0.0-rc.10', prerelease: true),
    ], channel: UpdateChannel.rc)?.tag, 'v2.0.0');
  });
  test('sorts by version, not API publication order', () {
    expect(select([releaseFixture('v1.1.0'), releaseFixture('v2.0.0'),
      releaseFixture('v1.9.0')])?.tag, 'v2.0.0');
  });
  test('never downgrades RC or reinstalls metadata-only changes', () {
    expect(select([releaseFixture('v1.9.0')], current: '2.0.0-rc.1'), isNull);
    expect(select([releaseFixture('v2.0.0+96')], current: '2.0.0+94'), isNull);
    expect(select([releaseFixture('v2.0.0')], current: '2.0.0-rc.1')?.tag, 'v2.0.0');
  });
  test('requires the exact architecture, never a substring match', () {
    expect(select([releaseFixture('v2.0.0', name: 'Pomodoist-aarch64.AppImage')]), isNull);
    expect(select([releaseFixture('v2.0.0', name: 'Pomodoist-x86_64.AppImage.exe')]), isNull);
    expect(select([releaseFixture('v2.0.0', name: 'Pomodoist-aarch64.AppImage')],
      target: const UpdateTarget(UpdateOS.linux, UpdateArch.arm64))?.tag, 'v2.0.0');
  });
  test('legacy Windows installer is x64 only', () {
    final release = releaseFixture('v2.0.0', name: 'Pomodoist-Setup.exe');
    expect(select([release], target: const UpdateTarget(UpdateOS.windows, UpdateArch.x64)), isNotNull);
    expect(select([release], target: const UpdateTarget(UpdateOS.windows, UpdateArch.arm64)), isNull);
  });
  test('fails closed without integrity metadata', () {
    expect(select([releaseFixture('v2.0.0', checksum: false)]), isNull);
    expect(select([releaseFixture('v2.0.0', checksum: false, digest: 'sha256:${'a' * 64}')]), isNotNull);
    expect(select([releaseFixture('v2.0.0', checksum: false, digest: 'md5:abc')]), isNull);
  });
  for (final url in [
    'http://github.com/Kabanya/Pomodoist/releases/download/v2.0.0/Pomodoist-x86_64.AppImage',
    'https://evil.example/Pomodoist-x86_64.AppImage',
    'https://github.com/other/repo/releases/download/v2.0.0/Pomodoist-x86_64.AppImage',
    'https://github.com/Kabanya/Pomodoist/releases/download/v1.0.0/Pomodoist-x86_64.AppImage',
  ]) {
    test('rejects untrusted or cross-release asset URL $url', () {
      expect(select([releaseFixture('v2.0.0', url: url)]), isNull);
    });
  }
  test('malformed release entries do not hide a valid update', () {
    expect(select([null, {}, {'tag_name': 42}, releaseFixture('v2.0.0')])?.tag, 'v2.0.0');
  });
  test('checksum is bound to the exact artifact filename', () {
    final hash = 'a' * 64;
    expect(parseUpdateChecksum('$hash *Pomodoist-Setup.exe\r\n', 'Pomodoist-Setup.exe'), hash);
    expect(() => parseUpdateChecksum('$hash other.exe', 'Pomodoist-Setup.exe'), throwsFormatException);
    expect(() => parseUpdateChecksum(hash, 'Pomodoist-Setup.exe'), throwsFormatException);
  });
}
