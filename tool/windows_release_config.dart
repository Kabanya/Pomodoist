import 'dart:convert';
import 'dart:io';

const windowsPackageIdentityName = 'com.finchforge.pomodoist';

final class WindowsReleaseVersion {
  const WindowsReleaseVersion._({
    required this.baseVersion,
    required this.buildNumber,
  });

  factory WindowsReleaseVersion.fromPubspec(
    String contents, {
    String? tag,
    int? previousBuildNumber,
  }) {
    final match = RegExp(
      r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(contents);
    if (match == null) {
      throw const FormatException('pubspec.yaml must contain version: X.Y.Z+N');
    }

    final parts = [
      for (var index = 1; index <= 4; index++) int.parse(match[index]!),
    ];
    if (parts.any((part) => part > 65535)) {
      throw const FormatException('MSIX version parts must be at most 65535');
    }

    final baseVersion = '${parts[0]}.${parts[1]}.${parts[2]}';
    if (tag != null && tag != 'v$baseVersion') {
      throw FormatException(
        'Git tag $tag does not match pubspec version $baseVersion',
      );
    }
    if (previousBuildNumber != null && parts[3] <= previousBuildNumber) {
      throw FormatException(
        'Build number ${parts[3]} must be greater than $previousBuildNumber',
      );
    }

    return WindowsReleaseVersion._(
      baseVersion: baseVersion,
      buildNumber: parts[3],
    );
  }

  final String baseVersion;
  final int buildNumber;

  String get msixVersion => '$baseVersion.$buildNumber';

  Map<String, Object> toJson() => {
    'baseVersion': baseVersion,
    'buildNumber': buildNumber,
    'msixVersion': msixVersion,
  };
}

String buildAppInstallerXml({
  required WindowsReleaseVersion version,
  required String publisher,
  required String repository,
}) {
  if (publisher.trim().isEmpty) {
    throw const FormatException('Publisher must not be empty');
  }
  if (!RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(repository)) {
    throw const FormatException('Repository must use owner/name format');
  }

  const escape = HtmlEscape(HtmlEscapeMode.attribute);
  final escapedPublisher = escape.convert(publisher);
  final escapedRepository = escape.convert(repository);
  final releaseBase =
      'https://github.com/$escapedRepository/releases/latest/download';
  final appInstallerUri = '$releaseBase/Pomodoist.appinstaller';
  final bundleUri = '$releaseBase/Pomodoist.msixbundle';

  return '''<?xml version="1.0" encoding="utf-8"?>
<AppInstaller xmlns="http://schemas.microsoft.com/appx/appinstaller/2021"
              Version="${version.msixVersion}"
              Uri="$appInstallerUri">
  <MainBundle Name="$windowsPackageIdentityName"
              Publisher="$escapedPublisher"
              Version="${version.msixVersion}"
              Uri="$bundleUri" />
  <UpdateSettings>
    <OnLaunch HoursBetweenUpdateChecks="12" />
  </UpdateSettings>
</AppInstaller>
''';
}

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty) {
      throw const FormatException('Expected metadata or appinstaller command');
    }
    final command = arguments.first;
    final options = _parseOptions(arguments.skip(1).toList());
    final pubspec = File(options['pubspec'] ?? 'pubspec.yaml');
    final tag = options['tag'];
    if (tag == null || tag.isEmpty) {
      throw const FormatException('--tag is required');
    }
    final previousBuild = options['previous-build'];
    final version = WindowsReleaseVersion.fromPubspec(
      await pubspec.readAsString(),
      tag: tag,
      previousBuildNumber: previousBuild == null
          ? null
          : int.parse(previousBuild),
    );

    switch (command) {
      case 'metadata':
        stdout.writeln(jsonEncode(version.toJson()));
      case 'appinstaller':
        final publisher = options['publisher'];
        final output = options['output'];
        if (publisher == null || output == null) {
          throw const FormatException(
            'appinstaller requires --publisher and --output',
          );
        }
        final target = File(output);
        await target.parent.create(recursive: true);
        await target.writeAsString(
          buildAppInstallerXml(
            version: version,
            publisher: publisher,
            repository: options['repository'] ?? 'Kabanya/Pomodoist',
          ),
        );
        stdout.writeln(target.absolute.path);
      default:
        throw FormatException('Unknown command: $command');
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 66;
  }
}

Map<String, String> _parseOptions(List<String> arguments) {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final name = arguments[index];
    if (!name.startsWith('--') || index + 1 >= arguments.length) {
      throw FormatException('Expected --name value, got $name');
    }
    options[name.substring(2)] = arguments[index + 1];
  }
  return options;
}
