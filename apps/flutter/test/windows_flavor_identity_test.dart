import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

/// The repository root, resolved from `apps/flutter`, which is the working
/// directory every `flutter test` run uses.
final String _repoRoot = Directory('../..').resolveSymbolicLinksSync();

String _read(String relativePath) =>
    File('$_repoRoot/$relativePath').readAsStringSync();

/// The `$PomodoistFlavors` table in `tool/windows/flavors.ps1`, keyed by flavor
/// name and then by the identity field the scripts read.
///
/// The table is a nested `[ordered]@{...}` literal of `Name = 'value'` pairs, so
/// the flavor header is a bare `name = [ordered]@{` line and every field below
/// it belongs to that flavor until the next header.
Map<String, Map<String, String>> _powerShellFlavorTable() {
  final table = <String, Map<String, String>>{};
  String? flavor;
  for (final line in _read('tool/windows/flavors.ps1').split('\n')) {
    final header = RegExp(
      r'^\s*(\w+)\s*=\s*\[ordered\]@\{\s*$',
    ).firstMatch(line);
    if (header != null) {
      flavor = header.group(1);
      table[flavor!] = <String, String>{};
      continue;
    }
    final entry = RegExp(r"^\s*(\w+)\s*=\s*'([^']*)'\s*$").firstMatch(line);
    if (entry != null && flavor != null) {
      table[flavor]![entry.group(1)!] = entry.group(2)!;
    }
  }
  return table;
}

/// The flavor table in `apps/flutter/windows/CMakeLists.txt`.
///
/// The shared defaults are assigned before the per-flavor `if`/`elseif` chain
/// and each branch overrides only what differs, so a variable resolves to its
/// branch assignment when there is one and to the default otherwise.
class _CmakeFlavorTable {
  _CmakeFlavorTable(this._defaults, this._branches);

  final Map<String, String> _defaults;
  final Map<String, Map<String, String>> _branches;

  String? valueFor(String flavor, String variable) =>
      _branches[flavor]?[variable] ?? _defaults[variable];

  bool hasVariable(String variable) =>
      _defaults.containsKey(variable) ||
      _branches.values.any((values) => values.containsKey(variable));
}

_CmakeFlavorTable _cmakeFlavorTable() {
  final defaults = <String, String>{};
  final branches = <String, Map<String, String>>{};
  String? branch;
  for (final line in _read('apps/flutter/windows/CMakeLists.txt').split('\n')) {
    final selector = RegExp(
      r'^\s*(?:if|elseif)\(POMODOIST_FLAVOR_NAME STREQUAL "([^"]+)"\)\s*$',
    ).firstMatch(line);
    if (selector != null) {
      branch = selector.group(1);
      branches[branch!] = <String, String>{};
      continue;
    }
    if (RegExp(r'^\s*else\(\)\s*$').hasMatch(line)) {
      branch = null;
      continue;
    }
    final assignment = RegExp(
      r'^\s*set\((POMODOIST_FLAVOR_[A-Z_]+)\s+(?:"([^"]*)"|([^)\s]+))\)\s*$',
    ).firstMatch(line);
    if (assignment == null) continue;
    final value = assignment.group(2) ?? assignment.group(3)!;
    (branch == null ? defaults : branches[branch]!)[assignment.group(1)!] =
        value;
  }
  return _CmakeFlavorTable(defaults, branches);
}

void main() {
  final flavors = _powerShellFlavorTable();
  final cmake = _cmakeFlavorTable();

  group('tool/windows/flavors.ps1', () {
    test('declares exactly the AppFlavor rows', () {
      expect(
        flavors.keys,
        unorderedEquals(AppFlavor.values.map((flavor) => flavor.name)),
      );
    });

    test('every identity value matches AppFlavor', () {
      for (final flavor in AppFlavor.values) {
        final row = flavors[flavor.name];
        expect(row, isNotNull, reason: flavor.name);
        expect(row!['DisplayName'], flavor.displayName, reason: flavor.name);
        expect(row['ApplicationId'], flavor.applicationId, reason: flavor.name);
        expect(row['UrlScheme'], flavor.urlScheme, reason: flavor.name);
        expect(row['ToastGuid'], flavor.windowsToastGuid, reason: flavor.name);
        expect(row['EntryPoint'], flavor.entrypoint, reason: flavor.name);
      }
    });

    test('only production keeps the conventional window class', () {
      expect(
        flavors['production']!['WindowClass'],
        'FLUTTER_RUNNER_WIN32_WINDOW',
      );
      for (final flavor in AppFlavor.values.where(
        (flavor) => !flavor.isProduction,
      )) {
        final windowClass = flavors[flavor.name]!['WindowClass']!;
        expect(
          windowClass,
          startsWith('FLUTTER_RUNNER_WIN32_WINDOW_'),
          reason: flavor.name,
        );
        expect(
          windowClass,
          isNot('FLUTTER_RUNNER_WIN32_WINDOW'),
          reason: '${flavor.name} must not share production\'s window class',
        );
      }
    });

    test('nothing that separates the installs is shared', () {
      for (final field in const [
        'DisplayName',
        'ApplicationId',
        'UrlScheme',
        'ToastGuid',
        'WindowClass',
        'IconFileName',
        'SetupBaseName',
        'BuildDirectory',
      ]) {
        final values = AppFlavor.values
            .map((flavor) => flavors[flavor.name]![field])
            .toList();
        expect(
          values.toSet(),
          hasLength(values.length),
          reason: '$field must differ per flavor',
        );
      }
    });

    test('production keeps the shipped artifact names', () {
      expect(flavors['production']!['SetupBaseName'], 'Pomodoist-Setup');
      expect(
        flavors['production']!['BuildDirectory'],
        r'build\flutter\windows\x64\production\runner\Release',
      );
    });

    test('each flavor packages its own Flutter output directory', () {
      for (final flavor in AppFlavor.values) {
        expect(
          flavors[flavor.name]!['BuildDirectory'],
          endsWith('\\windows\\x64\\${flavor.name}\\runner\\Release'),
          reason: flavor.name,
        );
      }
    });

    test('every flavor icon exists beside the runner', () {
      for (final flavor in AppFlavor.values) {
        final icon = flavors[flavor.name]!['IconFileName']!;
        expect(
          File(
            '$_repoRoot/apps/flutter/windows/runner/resources/$icon',
          ).existsSync(),
          isTrue,
          reason: '${flavor.name}: $icon',
        );
      }
    });

    test('every script that reads an identity loads the table', () {
      for (final script in const [
        'tool/windows/build.ps1',
        'tool/windows/run.ps1',
        'tool/windows/test_deep_link_forwarding.ps1',
        'tool/windows/installer/build.ps1',
        'tool/windows/installer/smoke.ps1',
        'tool/windows/installer/verify-contract.ps1',
      ]) {
        final source = _read(script);
        expect(
          source,
          contains('flavors.ps1'),
          reason: '$script never loads the shared flavor table',
        );
        expect(
          source,
          anyOf(
            contains('Get-PomodoistFlavor'),
            contains(r'$PomodoistFlavors'),
          ),
          reason: '$script loads the table but never reads it',
        );
      }
    });
  });

  group('apps/flutter/windows/CMakeLists.txt', () {
    test('falls back to production when no flavor was named', () {
      final source = _read('apps/flutter/windows/CMakeLists.txt');
      expect(
        source,
        contains(
          'if(NOT DEFINED FLUTTER_APP_FLAVOR OR FLUTTER_APP_FLAVOR STREQUAL "")',
        ),
      );
      expect(source, contains('set(FLUTTER_APP_FLAVOR "production")'));
      expect(
        source,
        contains(r'string(TOLOWER "${FLUTTER_APP_FLAVOR}" FLUTTER_APP_FLAVOR)'),
      );
    });

    test('rejects a flavor it does not know', () {
      final source = _read('apps/flutter/windows/CMakeLists.txt');
      expect(source, contains('message(FATAL_ERROR'));
      for (final flavor in AppFlavor.values) {
        expect(
          source,
          contains('POMODOIST_FLAVOR_NAME STREQUAL "${flavor.name}"'),
          reason: flavor.name,
        );
      }
    });

    test('every identity value matches AppFlavor', () {
      for (final flavor in AppFlavor.values) {
        expect(
          cmake.valueFor(flavor.name, 'POMODOIST_FLAVOR_DISPLAY_NAME'),
          flavor.displayName,
          reason: flavor.name,
        );
        expect(
          cmake.valueFor(flavor.name, 'POMODOIST_FLAVOR_APPLICATION_ID'),
          flavor.applicationId,
          reason: flavor.name,
        );
        expect(
          cmake.valueFor(flavor.name, 'POMODOIST_FLAVOR_URL_SCHEME'),
          flavor.urlScheme,
          reason: flavor.name,
        );
        expect(
          cmake.valueFor(flavor.name, 'POMODOIST_FLAVOR_TOAST_GUID'),
          flavor.windowsToastGuid,
          reason: flavor.name,
        );
      }
    });

    test('the compiled window class matches flavors.ps1', () {
      for (final flavor in AppFlavor.values) {
        expect(
          cmake.valueFor(flavor.name, 'POMODOIST_FLAVOR_WINDOW_CLASS'),
          flavors[flavor.name]!['WindowClass'],
          reason: flavor.name,
        );
      }
    });

    test('exactly one POMODOIST_FLAVOR_IS_* flag is set per flavor', () {
      const flags = {
        'POMODOIST_FLAVOR_IS_DEVELOPMENT': 'development',
        'POMODOIST_FLAVOR_IS_STAGING': 'staging',
        'POMODOIST_FLAVOR_IS_PRODUCTION': 'production',
      };
      for (final flavor in AppFlavor.values) {
        for (final flag in flags.entries) {
          expect(
            cmake.valueFor(flavor.name, flag.key),
            flag.value == flavor.name ? '1' : '0',
            reason: '${flavor.name} ${flag.key}',
          );
        }
      }
    });

    test('the executable keeps one name for every flavor', () {
      expect(
        _read('apps/flutter/windows/CMakeLists.txt'),
        contains('set(BINARY_NAME "pomodoist")'),
      );
    });
  });

  group('windows/runner/flavor_config.h.in', () {
    final source = _read('apps/flutter/windows/runner/flavor_config.h.in');

    test('every placeholder is set by windows/CMakeLists.txt', () {
      final placeholders = RegExp(
        r'@(POMODOIST_[A-Z_]+)@',
      ).allMatches(source).toList();
      expect(placeholders, isNotEmpty);
      for (final placeholder in placeholders) {
        expect(
          cmake.hasVariable(placeholder.group(1)!),
          isTrue,
          reason: '${placeholder.group(1)} is never set by CMake',
        );
      }
    });

    test('the _WIDE variants only wrap their plain macro', () {
      final wide = RegExp(
        r'#define (POMODOIST_[A-Z_]+)_WIDE L"@(POMODOIST_[A-Z_]+)@"',
      ).allMatches(source).toList();
      expect(wide, isNotEmpty);
      for (final definition in wide) {
        expect(definition.group(1), definition.group(2));
      }
    });
  });

  group('windows/runner/Runner.rc', () {
    final source = _read('apps/flutter/windows/runner/Runner.rc');

    test('renders the flavor display name into the version resource', () {
      expect(source, contains('#include "flavor_config.h"'));
      expect(
        source,
        contains('VALUE "FileDescription", POMODOIST_FLAVOR_DISPLAY_NAME'),
      );
      expect(
        source,
        contains('VALUE "ProductName", POMODOIST_FLAVOR_DISPLAY_NAME'),
      );
    });

    test('compiles each flavor its own icon and keeps pomodoist.exe', () {
      expect(source, contains('POMODOIST_FLAVOR_IS_DEVELOPMENT'));
      expect(source, contains('POMODOIST_FLAVOR_IS_STAGING'));
      expect(source, contains('VALUE "OriginalFilename", "pomodoist.exe"'));
      for (final flavor in AppFlavor.values) {
        final icon = flavors[flavor.name]!['IconFileName']!;
        expect(source, contains('"resources\\\\$icon"'), reason: flavor.name);
      }
    });
  });

  group('tool/windows/installer/Pomodoist.iss', () {
    final source = _read('tool/windows/installer/Pomodoist.iss');

    test('hardcodes no flavor identity', () {
      // The list verify-contract.ps1 enforces, repeated here so the drift is
      // caught on a host with no PowerShell.
      for (final fragment in const [
        'AppId=com.finchforge.pomodoist',
        r'Programs\Pomodoist',
        'OutputBaseFilename=Pomodoist-Setup',
        r'Software\Classes\pomodoist',
        r'Name: "{autoprograms}\Pomodoist"',
      ]) {
        expect(source.contains(fragment), isFalse, reason: fragment);
      }
    });

    test('derives the install directory and the uninstall key from /D', () {
      expect(source, contains('AppId={#AppIdentifier}'));
      expect(
        source,
        contains(r'DefaultDirName={localappdata}\Programs\{#AppDisplayName}'),
      );
      expect(source, contains('OutputBaseFilename={#SetupBaseFilename}'));
      expect(source, contains('UninstallDisplayName={#AppDisplayName}'));
    });

    test('every placeholder is supplied by the installer build script', () {
      final placeholders = RegExp(
        r'\{#([A-Za-z]\w*)\}',
      ).allMatches(source).map((match) => match.group(1)!).toSet();
      expect(placeholders, isNotEmpty);
      final supplied = RegExp(r'/D(\w+)=')
          .allMatches(_read('tool/windows/installer/build.ps1'))
          .map((match) => match.group(1)!)
          .toSet();
      expect(placeholders.difference(supplied), isEmpty);
    });
  });

  group('tool/windows/installer/build.ps1', () {
    final script = _read('tool/windows/installer/build.ps1');

    test('forwards every identity value from the flavor table', () {
      for (final argument in const [
        r'/DAppIdentifier=$($flavorConfig.ApplicationId)',
        r'/DAppDisplayName=$($flavorConfig.DisplayName)',
        r'/DAppUrlScheme=$($flavorConfig.UrlScheme)',
        r'/DAppToastGuid=$($flavorConfig.ToastGuid)',
        r'/DSetupBaseFilename=$($flavorConfig.SetupBaseName)',
      ]) {
        expect(script, contains(argument), reason: argument);
      }
      expect(script, contains(r'$flavorConfig.BuildDirectory'));
      expect(script, contains(r'$flavorConfig.IconFileName'));
    });
  });

  group('tool/windows/build.ps1', () {
    final script = _read('tool/windows/build.ps1');

    test('names the flavor and the entry point on every build', () {
      expect(
        script,
        contains("[ValidateSet('production', 'development', 'staging')]"),
      );
      expect(script, contains("'--flavor', \$Flavor"));
      expect(script, contains("'--target', \$Target"));
      expect(script, contains(r'$Target = $flavorConfig.EntryPoint'));
    });

    test('refuses an entry point that belongs to another flavor', () {
      expect(script, contains('Get-PomodoistFlavorForEntryPoint'));
      expect(script, contains('belongs to the'));
    });
  });

  group('windows/runner', () {
    test('the flavor table is resolved before the runner is configured', () {
      // runner/CMakeLists.txt materializes flavor_config.h from the variables in
      // the parent scope, so the parent has to read FLUTTER_APP_FLAVOR before it
      // descends into runner and after it descends into flutter, which is what
      // publishes FLUTTER_APP_FLAVOR in the first place.
      final source = _read('apps/flutter/windows/CMakeLists.txt');
      final published = source.indexOf(
        'add_subdirectory(\${FLUTTER_MANAGED_DIR})',
      );
      final resolved = source.indexOf(
        'POMODOIST_FLAVOR_DISPLAY_NAME "Pomodoist"',
      );
      final consumed = source.indexOf('add_subdirectory("runner")');

      expect(published, isNonNegative);
      expect(resolved, isNonNegative);
      expect(consumed, isNonNegative);
      expect(published, lessThan(resolved));
      expect(resolved, lessThan(consumed));
    });

    test('the runner compiles the generated identity', () {
      expect(
        _read('apps/flutter/windows/runner/CMakeLists.txt'),
        contains('"flavor_config.h.in"'),
      );
      final main = _read('apps/flutter/windows/runner/main.cpp');
      expect(main, contains('POMODOIST_FLAVOR_WINDOW_CLASS_WIDE'));
      expect(main, contains('POMODOIST_FLAVOR_DISPLAY_NAME_WIDE'));
      expect(main, contains('POMODOIST_FLAVOR_APPLICATION_ID_WIDE'));
      expect(
        _read('apps/flutter/windows/runner/win32_window.cpp'),
        contains('POMODOIST_FLAVOR_WINDOW_CLASS_WIDE'),
      );
    });
  });
}
