import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/platform/distraction_wayland_io.dart';

void main() {
  test('Sway follows only the focused app and strips private titles', () {
    final tree = {
      'type': 'root',
      'nodes': [
        {
          'type': 'workspace',
          'name': 'work "quoted";',
          'nodes': [
            {
              'id': 42,
              'app_id': 'org.example.Chat',
              'name': 'PRIVATE DOCUMENT',
              'focused': true,
              'scratchpad_state': 'none',
            },
            {'id': 43, 'app_id': 'org.example.Video', 'focused': false},
          ],
        },
      ],
    };
    final app = parseDistractionSwayWindow(tree)!;
    expect(app.id, 'linux:org.example.Chat');
    expect(app.key, '42');
    expect(app.workspaceName, 'work "quoted";');
    expect(jsonEncode(app.publicIdentity), isNot(contains('PRIVATE DOCUMENT')));
    expect(
      app.publicIdentity.keys,
      unorderedEquals(['id', 'name', 'platform']),
    );
  });
  test(
    'scratchpad, invalid public identities and shell windows are excluded',
    () {
      for (final id in [
        'org.example/Chat',
        'plasmashell',
        'com.finchforge.pomodoist',
      ]) {
        expect(
          parseDistractionSwayWindow({'id': 42, 'focused': true, 'app_id': id}),
          isNull,
        );
      }
      expect(
        parseDistractionSwayWindow({
          'id': 42,
          'focused': true,
          'app_id': 'org.example.Chat',
          'scratchpad_state': 'fresh',
        }),
        isNull,
      );
    },
  );
  test('Hyprland uses stable initial class and validated local address', () {
    final app = parseDistractionHyprlandWindow({
      'initialClass': 'org.example.Chat',
      'class': 'changed',
      'address': '0x123abc',
      'title': 'PRIVATE',
      'workspace': {'id': 3},
    })!;
    expect(app.id, 'linux:org.example.Chat');
    expect(app.workspace, 3);
    expect(jsonEncode(app.publicIdentity), isNot(contains('0x123abc')));
    expect(
      parseDistractionHyprlandWindow({
        'class': 'org.example.Chat',
        'address': '0x12; exec bad',
      }),
      isNull,
    );
  });
  test(
    'KWin script transmits public identity and minimizes exact rules only',
    () {
      final script = buildDistractionKwinScript(
        ':1.42',
        '/test',
        {'linux:org.example.Chat'},
        {'uuid-1': 'linux:org.example.Chat'},
      );
      expect(script, contains('blocked.indexOf(id)!==-1'));
      expect(script, contains('restore[key] === identity(w)'));
      expect(script, contains('w.minimized=true'));
      expect(script, isNot(contains('caption')));
      expect(script, isNot(contains('terminate')));
    },
  );
}
