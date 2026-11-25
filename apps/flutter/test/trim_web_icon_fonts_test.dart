import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/trim_web_icon_fonts.dart';

void main() {
  late Directory root;
  late Directory build;
  late File manifest;
  const regular = 'packages/lucide_icons_flutter/Lucide';
  const weighted = '${regular}300';
  const roboto = {
    'family': 'Roboto',
    'fonts': [
      {'asset': 'fonts/fallback/Roboto-Regular.ttf'},
    ],
  };
  const families = [
    roboto,
    {
      'family': regular,
      'fonts': [
        {'asset': 'packages/lucide_icons_flutter/assets/lucide.ttf'},
      ],
    },
    {
      'family': weighted,
      'fonts': [
        {'asset': 'packages/lucide_icons_flutter/assets/Lucide300.ttf'},
      ],
    },
    {
      'family': 'packages/shadcn_ui/Geist',
      'fonts': [
        {'asset': 'packages/shadcn_ui/fonts/Geist.ttf'},
      ],
    },
  ];

  setUp(() {
    root = Directory.systemTemp.createTempSync('pomodoist-web-fonts-');
    build = Directory('${root.path}/build');
    manifest = File('${build.path}/assets/FontManifest.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(families));
    File(
      '${build.path}/main.dart.js',
    ).writeAsStringSync('const family = "$regular";');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('omits only unused weighted Lucide families', () {
    trimWebIconFonts(build);

    expect(jsonDecode(manifest.readAsStringSync()), [
      roboto,
      families[1],
      families.last,
    ]);
  });

  test('refuses to remove an icon family used by a deferred JS part', () {
    File('${build.path}/main.dart.js_1.part.js').writeAsStringSync(
      'const icon = IconData(1, "Lucide300", "lucide_icons_flutter");',
    );
    expect(
      () => trimWebIconFonts(build),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains(weighted), contains('main.dart.js_1.part.js')),
        ),
      ),
    );
    expect(jsonDecode(manifest.readAsStringSync()), families);
  });
}
