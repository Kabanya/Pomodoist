import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/hyprland_global_shortcut.dart';

void main() {
  test('replace installs the requested global action', () async {
    final calls = <_Command>[];
    final shortcut = HyprlandGlobalShortcut(
      commandRunner: (executable, arguments) async {
        calls.add(_Command(executable, arguments));
        if (arguments.first == 'binds') {
          return ProcessResult(1, 0, '[]', '');
        }
        return ProcessResult(2, 0, 'ok', '');
      },
    );

    await shortcut.replace(
      portalTrigger: 'CTRL+ALT+space',
      appId: 'com.finchforge.pomodoist',
    );

    expect(calls, hasLength(2));
    expect(calls.first.executable, 'hyprctl');
    expect(calls.first.arguments, ['binds', '-j']);
    expect(calls.last.arguments.take(2), ['keyword', 'bindd']);
    expect(calls.last.arguments.last, contains('CTRL ALT, SPACE'));
    expect(
      calls.last.arguments.last,
      contains('com.finchforge.pomodoist:quick-add'),
    );
  });

  test('replace refuses to overwrite an occupied shortcut', () async {
    var calls = 0;
    final shortcut = HyprlandGlobalShortcut(
      commandRunner: (executable, arguments) async {
        calls++;
        return ProcessResult(1, 0, jsonEncode([_userBind()]), '');
      },
    );

    await expectLater(
      shortcut.replace(
        portalTrigger: 'CTRL+ALT+space',
        appId: 'com.finchforge.pomodoist',
      ),
      throwsA(isA<HyprlandShortcutConflict>()),
    );
    expect(calls, 1);
  });

  test('replace keeps its matching existing managed shortcut', () async {
    final calls = <_Command>[];
    final shortcut = HyprlandGlobalShortcut(
      commandRunner: (executable, arguments) async {
        calls.add(_Command(executable, arguments));
        return ProcessResult(1, 0, jsonEncode([_managedBind()]), '');
      },
    );

    await shortcut.replace(
      portalTrigger: 'CTRL+ALT+space',
      appId: 'com.finchforge.pomodoist',
    );

    expect(calls, hasLength(1));
  });

  test(
    'remove unbinds a managed shortcut after checking for collisions',
    () async {
      final calls = <_Command>[];
      final shortcut = HyprlandGlobalShortcut(
        commandRunner: (executable, arguments) async {
          calls.add(_Command(executable, arguments));
          if (arguments.first == 'binds') {
            return ProcessResult(1, 0, jsonEncode([_managedBind()]), '');
          }
          return ProcessResult(2, 0, 'ok', '');
        },
      );

      await shortcut.remove();

      expect(calls, hasLength(2));
      expect(calls.last.executable, 'hyprctl');
      expect(calls.last.arguments, ['keyword', 'unbind', 'CTRL ALT, SPACE']);
    },
  );

  test('remove preserves a user bind added on the same shortcut', () async {
    var calls = 0;
    final shortcut = HyprlandGlobalShortcut(
      commandRunner: (executable, arguments) async {
        calls++;
        return ProcessResult(
          1,
          0,
          jsonEncode([_managedBind(), _userBind()]),
          '',
        );
      },
    );

    await expectLater(
      shortcut.remove(),
      throwsA(isA<HyprlandShortcutCleanupConflict>()),
    );
    expect(calls, 1);
  });

  test('replace maps portal modifiers and named keys to Hyprland', () async {
    _Command? call;
    final shortcut = HyprlandGlobalShortcut(
      commandRunner: (executable, arguments) async {
        call = _Command(executable, arguments);
        if (arguments.first == 'binds') {
          return ProcessResult(1, 0, '[]', '');
        }
        return ProcessResult(2, 0, 'ok', '');
      },
    );

    await shortcut.replace(
      portalTrigger: 'CTRL+LOGO+Page_Up',
      appId: 'appimagekit_123-Pomodoist',
    );

    expect(call!.arguments.last, contains('CTRL SUPER, PAGE_UP'));
    expect(
      call!.arguments.last,
      contains('appimagekit_123-Pomodoist:quick-add'),
    );
  });
}

Map<String, Object> _managedBind() => {
  'modmask': 12,
  'key': 'SPACE',
  'keycode': 0,
  'submap': 'global',
  'description': hyprlandManagedShortcutDescription,
  'dispatcher': 'global',
  'arg': 'com.finchforge.pomodoist:quick-add',
};

Map<String, Object> _userBind() => {
  'modmask': 12,
  'key': 'Space',
  'keycode': 0,
  'submap': 'global',
  'description': 'User shortcut',
  'dispatcher': 'exec',
  'arg': 'notify-send occupied',
};

class _Command {
  const _Command(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
