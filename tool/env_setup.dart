import 'dart:convert';
import 'dart:io';

const _profiles = <String, String>{
  'LOCAL__': '.env.local',
  'STAGING__': '.env.staging',
  'TESTFLIGHT__': '.env.testflight',
  'WINDOWS__': '.env.windows',
  'LINUX__': '.env.linux',
  'PRIVATE__': '.env.private',
  'DEPLOY__': '.env.deploy',
};

final _namePattern = RegExp(r'^[A-Z][A-Z0-9_]*$');

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty) throw const _EnvError('expected a command');
    final command = arguments.first;
    final options = _options(arguments.skip(1).toList());
    switch (command) {
      case 'bootstrap':
        await _bootstrap(
          Directory(options['--root'] ?? Directory.current.path),
        );
      case 'sync':
        await _sync(Directory(options['--root'] ?? Directory.current.path));
      case 'value':
        final env = _requiredOption(options, '--env');
        final key = _requiredOption(options, '--key');
        final value = (await _parse(File(env)))[key];
        if (value == null || value.isEmpty) {
          throw _EnvError('$key is missing or empty');
        }
        stdout.write(value);
      case 'set':
        final env = File(_requiredOption(options, '--env'));
        final key = _requiredOption(options, '--key');
        final value = await utf8.decoder.bind(stdin).join();
        await _setValue(env, key, value);
      case 'write-asc-key':
        await _writeAscKey(
          File(_requiredOption(options, '--env')),
          File(_requiredOption(options, '--output')),
        );
      case 'validate-staging':
        final env = await _parse(File(_requiredOption(options, '--env')));
        if ((env['APPLE_PRIVATE_KEY_BASE64'] ?? '').isEmpty) {
          throw const _EnvError('APPLE_PRIVATE_KEY_BASE64 is missing or empty');
        }
      default:
        throw _EnvError('unknown command: $command');
    }
  } on _EnvError catch (error) {
    stderr.writeln('Environment setup error: ${error.message}');
    exitCode = 64;
  } on FileSystemException {
    stderr.writeln(
      'Environment setup error: a configuration file could not be read or written',
    );
    exitCode = 66;
  }
}

Future<void> _setValue(File file, String key, String value) async {
  if (!_namePattern.hasMatch(key)) throw _EnvError('invalid key $key');
  if (value.isEmpty) throw _EnvError('$key is missing or empty');
  if (value.contains('\n') || value.contains('\r')) {
    throw _EnvError('$key must be a single line');
  }

  if (!await file.exists()) await file.writeAsString('');
  final values = await _parse(file);
  if (!values.containsKey(key)) {
    await _append(file, [MapEntry(key, value)]);
  } else {
    final lines = await file.readAsLines();
    final content = lines
        .map((line) {
          final separator = line.indexOf('=');
          if (separator < 1 || line.substring(0, separator).trim() != key) {
            return line;
          }
          return '$key=$value';
        })
        .join('\n');
    await file.writeAsString('$content\n', flush: true);
  }
  await _restrict(file);
}

Future<void> _bootstrap(Directory root) async {
  final template = File('${root.path}/.env.example');
  final master = File('${root.path}/.env.setup');
  if (await master.exists()) return;
  await master.writeAsString(await template.readAsString());
  await _restrict(master);
  stdout.writeln(
    'Created .env.setup. Fill it, then run make setup-flutter '
    'to generate the environment files.',
  );
}

Future<void> _sync(Directory root) async {
  final template = File('${root.path}/.env.example');
  final master = File('${root.path}/.env.setup');
  final templateValues = await _parse(template, requireProfilePrefix: true);
  final masterValues = await _parse(master, requireProfilePrefix: true);

  for (final key in masterValues.keys) {
    if (!templateValues.containsKey(key)) {
      throw _EnvError('unknown key $key in .env.setup');
    }
  }

  final missingMaster = templateValues.keys
      .where((key) => !masterValues.containsKey(key))
      .toList();
  if (missingMaster.isNotEmpty) {
    await _append(
      master,
      missingMaster.map((key) => MapEntry(key, templateValues[key]!)),
    );
    for (final key in missingMaster) {
      masterValues[key] = templateValues[key]!;
    }
  }
  await _restrict(master);

  for (final profile in _profiles.entries) {
    final selected = <String, String>{};
    for (final entry in masterValues.entries) {
      if (entry.key.startsWith(profile.key)) {
        selected[entry.key.substring(profile.key.length)] = entry.value;
      }
    }
    if (selected.isEmpty) continue;

    final destination = File('${root.path}/${profile.value}');
    if (!await destination.exists()) {
      await destination.writeAsString(
        '# Generated from .env.setup; rerun make setup-flutter to sync non-empty values.\n'
        '${selected.entries.map((entry) => '${entry.key}=${entry.value}').join('\n')}\n',
      );
    } else {
      final existing = await _parse(destination);
      final additions = selected.entries.where(
        (entry) => entry.value.isNotEmpty && !existing.containsKey(entry.key),
      );
      final updates = <String, String>{
        for (final entry in selected.entries)
          if (entry.value.isNotEmpty && existing[entry.key] != entry.value)
            entry.key: entry.value,
      };
      await _append(destination, additions);
      if (updates.isNotEmpty) {
        final lines = await destination.readAsLines();
        final content = lines
            .map((line) {
              final separator = line.indexOf('=');
              if (separator < 1) return line;
              final name = line.substring(0, separator).trim();
              final update = updates[name];
              return update == null ? line : '$name=$update';
            })
            .join('\n');
        await destination.writeAsString('$content\n', flush: true);
      }
    }
    await _restrict(destination);
  }

  stdout.writeln('Environment files are ready.');
}

Future<void> _writeAscKey(File env, File output) async {
  final encoded = (await _parse(env))['ASC_PRIVATE_KEY_BASE64'];
  if (encoded == null || encoded.isEmpty) {
    throw const _EnvError('ASC_PRIVATE_KEY_BASE64 is missing or empty');
  }

  late final List<int> bytes;
  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    throw const _EnvError('ASC_PRIVATE_KEY_BASE64 is not valid base64');
  }
  final text = utf8.decode(bytes, allowMalformed: true);
  if (!text.startsWith('-----BEGIN PRIVATE KEY-----') ||
      !text.contains('-----END PRIVATE KEY-----')) {
    throw const _EnvError('ASC_PRIVATE_KEY_BASE64 is not a PKCS#8 private key');
  }

  await output.parent.create(recursive: true);
  await output.writeAsBytes(bytes, flush: true);
  await _restrict(output);
}

Future<Map<String, String>> _parse(
  File file, {
  bool requireProfilePrefix = false,
}) async {
  if (!await file.exists()) throw _EnvError('missing ${file.path}');
  final values = <String, String>{};
  final lines = await file.readAsLines();
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator < 1) {
      throw _EnvError(
        'invalid assignment at line ${index + 1} in ${file.path}',
      );
    }
    final name = line.substring(0, separator).trim();
    if (!_namePattern.hasMatch(name)) {
      throw _EnvError('invalid key at line ${index + 1} in ${file.path}');
    }
    if (requireProfilePrefix &&
        !_profiles.keys.any((prefix) => name.startsWith(prefix))) {
      throw _EnvError('key $name has no environment prefix');
    }
    if (values.containsKey(name)) throw _EnvError('duplicate key $name');
    values[name] = line.substring(separator + 1);
  }
  return values;
}

Map<String, String> _options(List<String> arguments) {
  if (arguments.length.isOdd) throw const _EnvError('invalid options');
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final name = arguments[index];
    if (!name.startsWith('--') || result.containsKey(name)) {
      throw const _EnvError('invalid options');
    }
    result[name] = arguments[index + 1];
  }
  return result;
}

String _requiredOption(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.isEmpty) throw _EnvError('$name is required');
  return value;
}

Future<void> _append(
  File file,
  Iterable<MapEntry<String, String>> entries,
) async {
  final additions = entries.toList();
  if (additions.isEmpty) return;
  final current = await file.readAsString();
  final prefix = current.isEmpty || current.endsWith('\n') ? '' : '\n';
  await file.writeAsString(
    '$prefix${additions.map((entry) => '${entry.key}=${entry.value}').join('\n')}\n',
    mode: FileMode.append,
    flush: true,
  );
}

Future<void> _restrict(File file) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', ['600', file.path]);
  if (result.exitCode != 0) throw _EnvError('could not restrict ${file.path}');
}

class _EnvError implements Exception {
  const _EnvError(this.message);

  final String message;
}
