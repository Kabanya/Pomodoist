import 'dart:convert';
import 'dart:io';

const _lucidePackage = 'packages/lucide_icons_flutter/';
final _weightedLucide = RegExp(r'\bLucide[1-6]00\b');
final _appScript = RegExp(r'^main\.dart\.js(?:_\d+\.part\.js)?$');

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart tool/trim_web_icon_fonts.dart BUILD_WEB');
    exitCode = 64;
    return;
  }
  trimWebIconFonts(Directory(args[0]));
}

void trimWebIconFonts(Directory build) {
  final assets = Directory('${build.path}/assets');
  final manifest = File('${assets.path}/FontManifest.json');
  final families = (jsonDecode(manifest.readAsStringSync()) as List<Object?>)
      .cast<Map<String, Object?>>();
  final weightedFamilies = {
    for (final weight in [100, 200, 300, 400, 500, 600])
      '${_lucidePackage}Lucide$weight',
  };
  final fontsToRemove = weightedFamilies.intersection(
    families.map((entry) => entry['family']).whereType<String>().toSet(),
  );

  final entrypoint = File('${build.path}/main.dart.js');
  if (!entrypoint.existsSync()) {
    throw StateError('Missing web entrypoint: ${entrypoint.path}');
  }
  for (final file in build.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (!_appScript.hasMatch(name)) continue;
    for (final match in _weightedLucide.allMatches(file.readAsStringSync())) {
      final family = '$_lucidePackage${match[0]}';
      if (fontsToRemove.contains(family)) {
        throw StateError('$name uses $family, which is marked for removal');
      }
    }
  }

  final startupFonts = [
    for (final family in families)
      if (!fontsToRemove.contains(family['family'])) family,
  ];
  manifest.writeAsStringSync(jsonEncode(startupFonts));
}
