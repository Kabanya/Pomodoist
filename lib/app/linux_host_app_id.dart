import 'dart:io';

const pomodoistApplicationId = 'com.finchforge.pomodoist';

class LinuxHostAppIdResolver {
  LinuxHostAppIdResolver({Map<String, String>? environment})
    : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  Future<String> resolve() async {
    final applicationDirectories = _hostApplicationDirectories();
    for (final directory in applicationDirectories) {
      final desktop = File('${directory.path}/$pomodoistApplicationId.desktop');
      if (await desktop.exists()) return pomodoistApplicationId;
    }

    final appImage = _environment['APPIMAGE'];
    if (appImage == null || appImage.isEmpty) return pomodoistApplicationId;
    for (final directory in applicationDirectories) {
      if (!await directory.exists()) continue;
      try {
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is! File || !entry.path.endsWith('.desktop')) continue;
          final contents = await entry.readAsString();
          if (!_describesAppImage(contents, appImage)) continue;
          return entry.uri.pathSegments.last.replaceFirst(
            RegExp(r'\.desktop$'),
            '',
          );
        }
      } on FileSystemException {
        // An unreadable data directory cannot describe this application.
      }
    }
    return pomodoistApplicationId;
  }

  List<Directory> _hostApplicationDirectories() {
    final roots = <String>[];
    final dataHome = _environment['XDG_DATA_HOME'];
    if (dataHome != null && dataHome.isNotEmpty) {
      roots.add(dataHome);
    } else {
      final home = _environment['HOME'];
      if (home != null && home.isNotEmpty) roots.add('$home/.local/share');
    }

    final configuredDataDirs = _environment['XDG_DATA_DIRS'];
    final dataDirs = configuredDataDirs == null
        ? const ['/usr/local/share', '/usr/share']
        : configuredDataDirs
              .split(':')
              .where((directory) => directory.isNotEmpty);
    roots.addAll(dataDirs);

    final appDir = _environment['APPDIR'];
    final seen = <String>{};
    return roots
        .map((root) => Directory(root).absolute.path)
        .where(
          (root) =>
              appDir == null ||
              appDir.isEmpty ||
              !_isInside(root, Directory(appDir).absolute.path),
        )
        .where(seen.add)
        .map((root) => Directory('$root/applications'))
        .toList();
  }

  bool _describesAppImage(String contents, String appImage) {
    for (final line in contents.split('\n')) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key == 'TryExec' && _samePath(value, appImage)) return true;
      if (key == 'Exec') {
        final executable = _desktopExecExecutable(value);
        if (executable != null && _samePath(executable, appImage)) return true;
      }
    }
    return false;
  }
}

bool _isInside(String path, String directory) {
  return path == directory || path.startsWith('$directory/');
}

bool _samePath(String first, String second) {
  String normalize(String value) {
    final file = File(value);
    try {
      return file.resolveSymbolicLinksSync();
    } on FileSystemException {
      return file.absolute.path;
    }
  }

  return normalize(first) == normalize(second);
}

String? _desktopExecExecutable(String value) {
  if (value.isEmpty) return null;
  if (!value.startsWith('"')) return value.split(RegExp(r'\s')).first;
  final result = StringBuffer();
  var escaped = false;
  for (var index = 1; index < value.length; index++) {
    final character = value[index];
    if (escaped) {
      result.write(character);
      escaped = false;
    } else if (character == r'\') {
      escaped = true;
    } else if (character == '"') {
      return result.toString();
    } else {
      result.write(character);
    }
  }
  return null;
}
