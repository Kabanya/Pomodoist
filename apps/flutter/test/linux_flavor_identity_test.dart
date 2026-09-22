import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/database_directory_io.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

/// Pins the Linux identity of the three flavors to [AppFlavor].
///
/// The Linux build takes the flavor from `--flavor`, the packaging scripts take
/// it from the bundle path, and the installer writes the desktop entry — three
/// places that must agree on one table. These tests read the CMake tables, the
/// templates and the shell table and compare them with the Dart one, so a
/// flavor that is renamed in one place fails here instead of producing an
/// artifact whose identity and binary disagree.
void main() {
  tearDown(() => setAppFlavor(buildTimeAppFlavor ?? AppFlavor.production));

  final cmake = File('linux/CMakeLists.txt').readAsStringSync();
  final runnerCmake = File('linux/runner/CMakeLists.txt').readAsStringSync();
  final application = File('linux/runner/my_application.cc').readAsStringSync();
  final desktopTemplate = File(
    'linux/packaging/app.desktop.in',
  ).readAsStringSync();
  final metainfoTemplate = File(
    'linux/packaging/app.metainfo.xml.in',
  ).readAsStringSync();

  test('the CMake flavor table mirrors AppFlavor', () {
    for (final flavor in AppFlavor.values) {
      final block = _flavorBlock(cmake, flavor);

      expect(
        block,
        contains('set(APPLICATION_ID "${flavor.applicationId}")'),
        reason: '${flavor.name} must build with its own application id',
      );
      expect(
        block,
        contains('set(APP_DISPLAY_NAME "${flavor.displayName}")'),
        reason: '${flavor.name} must build with its own display name',
      );
      for (final other in AppFlavor.values.where((it) => it != flavor)) {
        expect(
          block,
          isNot(contains('set(APPLICATION_ID "${other.applicationId}")')),
          reason: 'the ${flavor.name} branch must not carry ${other.name}',
        );
        expect(
          block,
          isNot(contains('set(APP_DISPLAY_NAME "${other.displayName}")')),
          reason: 'the ${flavor.name} branch must not carry ${other.name}',
        );
      }
    }
  });

  test('an unflavored build keeps the production identity', () {
    final defaults = _defaultFlavorBlock(cmake);

    expect(
      defaults,
      contains('set(APPLICATION_ID "${AppFlavor.production.applicationId}")'),
    );
    expect(
      defaults,
      contains('set(APP_DISPLAY_NAME "${AppFlavor.production.displayName}")'),
    );
  });

  test('an unknown flavor fails the configure step', () {
    expect(
      cmake,
      contains('elseif(NOT FLUTTER_APP_FLAVOR STREQUAL "")'),
      reason: 'only an empty flavor may fall through to production',
    );
    expect(cmake, contains('message(FATAL_ERROR'));
  });

  test('every named flavor is handled before the unknown-flavor guard', () {
    // The release targets pass --flavor production, so a flavor that is only
    // reachable through the default identity still reaches the guard as a
    // non-empty value and aborts the configure step. Each named flavor
    // therefore needs a branch of its own above the guard, and the guard must
    // stay the last thing the table does.
    final guard = cmake.indexOf('elseif(NOT FLUTTER_APP_FLAVOR STREQUAL "")');
    expect(guard, isNonNegative, reason: 'the guard must stay in the table');
    final failure = cmake.indexOf('message(FATAL_ERROR', guard);
    expect(
      failure,
      isNonNegative,
      reason: 'the guard must refuse an unknown flavor',
    );

    for (final flavor in AppFlavor.values) {
      final branch = cmake.indexOf(
        'FLUTTER_APP_FLAVOR STREQUAL "${flavor.name}"',
      );
      expect(
        branch,
        isNonNegative,
        reason:
            '${flavor.name} is passed to --flavor, so it needs a branch '
            'before the guard rather than falling through to the default '
            'identity',
      );
      expect(
        branch,
        lessThan(guard),
        reason: 'the ${flavor.name} branch must precede the guard',
      );
    }
  });

  test('the runner compiles the flavor identity in', () {
    expect(runnerCmake, contains(r'-DAPPLICATION_ID="${APPLICATION_ID}"'));
    expect(runnerCmake, contains(r'APP_DISPLAY_NAME="${APP_DISPLAY_NAME}"'));
    expect(application, contains('g_set_prgname(APPLICATION_ID)'));
    expect(application, contains('"application-id", APPLICATION_ID'));
    expect(application, contains('APP_DISPLAY_NAME'));
    for (final flavor in AppFlavor.values) {
      expect(
        application,
        isNot(contains(flavor.applicationId)),
        reason: 'the runner must not hardcode an application id',
      );
    }
  });

  test(
    'the desktop entry and metainfo take their identity from the flavor',
    () {
      expect(desktopTemplate, contains('Name=@DISPLAY_NAME@'));
      expect(desktopTemplate, contains('Icon=@APPLICATION_ID@'));
      expect(desktopTemplate, contains('StartupWMClass=@APPLICATION_ID@'));
      expect(
        desktopTemplate,
        contains('MimeType=x-scheme-handler/@URL_SCHEME@;'),
      );
      expect(metainfoTemplate, contains('<id>@APPLICATION_ID@</id>'));
      expect(metainfoTemplate, contains('<name>@DISPLAY_NAME@</name>'));
      expect(
        metainfoTemplate,
        contains('<launchable type="desktop-id">@APPLICATION_ID@.desktop'),
      );
      for (final flavor in AppFlavor.values) {
        expect(
          desktopTemplate,
          isNot(contains(flavor.applicationId)),
          reason: 'the desktop entry must stay flavor-agnostic',
        );
        expect(
          metainfoTemplate,
          isNot(contains(flavor.applicationId)),
          reason: 'the metainfo must stay flavor-agnostic',
        );
      }
    },
  );

  test('the shell flavor table mirrors AppFlavor', () {
    for (final flavor in AppFlavor.values) {
      expect(
        _flavorFunction('pomodoist_flavor_application_id', flavor.name),
        flavor.applicationId,
      );
      expect(
        _flavorFunction('pomodoist_flavor_display_name', flavor.name),
        flavor.displayName,
      );
      expect(
        _flavorFunction('pomodoist_flavor_url_scheme', flavor.name),
        flavor.urlScheme,
      );
    }
  });

  test('the shell flavor table rejects a flavor it does not know', () {
    final result = _bash('pomodoist_flavor_application_id windows');

    expect(result.exitCode, 64);
    expect(result.stderr.toString(), contains('Unknown Pomodoist flavor'));
  });

  test('installs, artifacts and icons are unique per flavor', () {
    final installNames = <String>{};
    final artifacts = <String>{};
    final icons = <String>{};

    for (final flavor in AppFlavor.values) {
      final installName = _flavorFunction(
        'pomodoist_flavor_install_name',
        flavor.name,
      );
      expect(
        installNames.add(installName),
        isTrue,
        reason: '${flavor.name} must install under a name of its own',
      );
      expect(
        installName,
        isNot(flavor.applicationId),
        reason: 'the install name and the data directory are separate names',
      );

      expect(
        artifacts.add(
          _flavorFunction('pomodoist_flavor_artifact_name', flavor.name),
        ),
        isTrue,
        reason: '${flavor.name} must publish an artifact of its own',
      );

      final icon = _flavorFunction(
        'pomodoist_flavor_icon_path',
        flavor.name,
        _appRoot,
      );
      expect(icon, '$_appRoot/web/icons/${flavor.name}/Icon-512.png');
      expect(icons.add(icon), isTrue);
      expect(
        File(icon).existsSync(),
        isTrue,
        reason: 'the packaging scripts must point at an icon that exists',
      );
    }
  });

  test('the flavor icons the packages install are committed', () {
    final git = _gitExecutable();

    for (final relative in [
      for (final flavor in AppFlavor.values)
        'web/icons/${flavor.name}/Icon-512.png',
      'web/icons/Icon-512.png',
    ]) {
      expect(
        File('$_appRoot/$relative').existsSync(),
        isTrue,
        reason: 'the packaging scripts must point at an icon that exists',
      );
      final tracked = Process.runSync(git, [
        'ls-files',
        '--error-unmatch',
        relative,
      ], workingDirectory: _appRoot);
      expect(
        tracked.exitCode,
        0,
        reason:
            '$relative must be committed and not ignored: the release '
            'builds start from a clean checkout, where an untracked icon the '
            'packaging scripts install does not exist',
      );
    }
  });

  test('no flavor writes its data into its own install directory', () async {
    final root = await Directory.systemTemp.createTemp(
      'pomodoist-flavor-identity-',
    );
    addTearDown(() => root.delete(recursive: true));

    for (final flavor in AppFlavor.values) {
      setAppFlavor(flavor);
      final directory = await linuxApplicationDataDirectory(
        environment: {'XDG_DATA_HOME': root.path},
      );
      final installName = _flavorFunction(
        'pomodoist_flavor_install_name',
        flavor.name,
      );

      expect(
        directory.path,
        isNot('${root.path}/$installName'),
        reason: '${flavor.name} must not write into its installed bundle',
      );
    }
  });
}

/// Returns the identity branch of [cmake] for [flavor].
///
/// The production identity is the default that precedes the `if`, so only the
/// development and staging identities have a branch of their own.
String _flavorBlock(String cmake, AppFlavor flavor) {
  if (flavor == AppFlavor.production) return _defaultFlavorBlock(cmake);
  final marker = 'if(FLUTTER_APP_FLAVOR STREQUAL "${flavor.name}")';
  final start = cmake.indexOf(marker);
  if (start < 0) {
    fail('linux/CMakeLists.txt has no ${flavor.name} branch.');
  }
  final branch = cmake.substring(start + marker.length);
  final end = RegExp(r'(elseif\(|else\(|endif\()').firstMatch(branch);
  return end == null ? branch : branch.substring(0, end.start);
}

String _defaultFlavorBlock(String cmake) =>
    cmake.substring(0, cmake.indexOf('if(FLUTTER_APP_FLAVOR'));

String _flavorFunction(String function, String flavor, [String? appRoot]) {
  final arguments = [
    _quote(flavor),
    if (appRoot != null) _quote(appRoot),
  ].join(' ');
  final result = _bash('$function $arguments');

  expect(result.exitCode, 0, reason: result.stderr.toString());
  return result.stdout.toString().trim();
}

ProcessResult _bash(String command) {
  return Process.runSync(
    'bash',
    ['-c', 'source ${_quote('$_repoRoot/tool/linux/flavor.sh')} && $command'],
    workingDirectory: _repoRoot,
    environment: const {'POMODOIST_ICON': ''},
  );
}

String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

String _gitExecutable() {
  final lookup = Process.runSync('which', const ['git']);
  if (lookup.exitCode != 0) {
    throw StateError('Git is required for this test.');
  }
  return lookup.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
}

String get _repoRoot =>
    Directory('../..').resolveSymbolicLinksSync().replaceAll(r'\', '/');

String get _appRoot => '$_repoRoot/apps/flutter';
