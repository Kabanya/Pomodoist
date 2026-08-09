import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

const _firstPartyPrefixes = <String>['../../../lib/'];

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/prepare_sentry_sourcemaps.dart '
      '<source-map> <repository-root>',
    );
    exitCode = 64;
    return;
  }

  await prepareSentrySourceMap(arguments[0], arguments[1]);
}

Future<void> prepareSentrySourceMap(
  String sourceMapPath,
  String repositoryRootPath,
) async {
  final mapFile = File(sourceMapPath);
  final repositoryRoot = await _canonicalRepositoryRoot(repositoryRootPath);
  final decoded = jsonDecode(await mapFile.readAsString());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Source map must be a JSON object');
  }
  final rawSources = decoded['sources'];
  if (rawSources is! List || rawSources.any((source) => source is! String)) {
    throw const FormatException('Source map sources must be strings');
  }

  var appSourceCount = 0;
  var includesMain = false;
  final sources = rawSources.cast<String>();
  final sanitizedSources = <String>[];
  final sourcesContent = <String?>[];
  for (var index = 0; index < sources.length; index += 1) {
    final source = sources[index];
    final prefix = _firstPartyPrefixes.where(source.startsWith).firstOrNull;
    if (prefix == null) {
      sanitizedSources.add(_sanitizedThirdPartySource(source, index));
      sourcesContent.add(null);
      continue;
    }

    sanitizedSources.add(source);
    final relative = source.substring('../../../'.length);
    final sourceFile = await _canonicalFirstPartySource(
      repositoryRoot: repositoryRoot,
      relative: relative,
      displayPath: source,
    );
    sourcesContent.add(await sourceFile.readAsString());
    if (prefix == '../../../lib/') {
      appSourceCount += 1;
      includesMain = includesMain || relative == 'lib/main.dart';
    }
  }

  if (!includesMain || appSourceCount == 0) {
    throw StateError('Expected Pomodoist lib sources were not embedded');
  }
  decoded['sources'] = sanitizedSources;
  decoded['sourcesContent'] = sourcesContent;
  await mapFile.writeAsString('${jsonEncode(decoded)}\n', flush: true);
  stdout.writeln('Embedded $appSourceCount Pomodoist lib sources.');
}

String _sanitizedThirdPartySource(String source, int index) {
  if (!path.posix.isAbsolute(source) && !path.windows.isAbsolute(source)) {
    return source;
  }
  final fileName = path.posix.basename(source.replaceAll('\\', '/'));
  return 'third-party:///$index/${Uri.encodeComponent(fileName)}';
}

Future<String> _canonicalRepositoryRoot(String value) async {
  try {
    final canonical = path.normalize(
      await Directory(path.absolute(value)).resolveSymbolicLinks(),
    );
    if (await FileSystemEntity.type(canonical, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Repository root is not a directory');
    }
    return canonical;
  } on FileSystemException {
    throw const FormatException('Repository root is unavailable');
  }
}

Future<File> _canonicalFirstPartySource({
  required String repositoryRoot,
  required String relative,
  required String displayPath,
}) async {
  if (path.isAbsolute(relative) ||
      path.split(relative).any((component) => component == '..')) {
    throw FormatException('Invalid first-party source path: $displayPath');
  }
  final candidate = path.normalize(path.join(repositoryRoot, relative));
  if (!path.isWithin(repositoryRoot, candidate)) {
    throw FormatException(
      'First-party source escapes repository: $displayPath',
    );
  }

  var current = repositoryRoot;
  final components = path.split(relative);
  for (var index = 0; index < components.length; index += 1) {
    current = path.join(current, components[index]);
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FormatException(
        'Symlinked first-party sources are forbidden: $displayPath',
      );
    }
    if (type == FileSystemEntityType.notFound) {
      throw FormatException(
        'Referenced first-party source is missing: $displayPath',
      );
    }
    final finalComponent = index == components.length - 1;
    if ((!finalComponent && type != FileSystemEntityType.directory) ||
        (finalComponent && type != FileSystemEntityType.file)) {
      throw FormatException('Invalid first-party source type: $displayPath');
    }
  }

  late final String canonicalSource;
  try {
    canonicalSource = path.normalize(
      await File(candidate).resolveSymbolicLinks(),
    );
  } on FileSystemException {
    throw FormatException(
      'Referenced first-party source is unavailable: $displayPath',
    );
  }
  if (!path.isWithin(repositoryRoot, canonicalSource)) {
    throw FormatException(
      'First-party source escapes repository: $displayPath',
    );
  }
  return File(canonicalSource);
}
