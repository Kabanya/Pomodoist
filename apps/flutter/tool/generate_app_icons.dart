// Generates every platform app icon from the three master PNGs.
//
// The masters live in `assets/branding/app_icons/` and are the only icon
// artwork in the repository a human edits. They are square, full bleed and
// opaque: `pomodoist_icon_development.png` and `pomodoist_icon_staging.png` are
// 1254x1254, `pomodoist_icon_production.png` is 1024x1024. Everything below is
// a resize of one of them, so an icon change is a master change plus a rerun.
//
// Usage, from `apps/flutter`:
//
//   dart run tool/generate_app_icons.dart           # regenerate in place
//   dart run tool/generate_app_icons.dart --check   # verify committed assets
//
// `--check` regenerates everything in memory, compares byte for byte against
// the committed files, validates each asset's dimensions, format and alpha
// policy, validates that every required platform slot exists, and exits
// non-zero listing every mismatch. CI runs `--check` only; a normal build never
// invokes this script.
//
// Flavor identity (display name, directory name) is read from
// `lib/domain/models/app_flavor.dart` so the icons cannot drift from the
// platform configuration.
//
// Two deliberate asymmetries:
//
//  * `Contents.json` is written for the development and staging appiconsets
//    only. The production ones are Xcode-managed and their byte layout is
//    Xcode's, so the script validates them structurally instead of rewriting
//    them.
//  * `web/manifest.json` keeps its existing path and JSON shape; the two extra
//    manifests are the same shape with the other flavors' identity.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pomodoist/domain/models/app_flavor.dart';

/// Directory (relative to `apps/flutter`) holding the three master images.
const _masterDirectory = 'assets/branding/app_icons';

/// Fraction of the macOS canvas the rounded artwork occupies.
const _macosCanvasFraction = 0.895;

/// Corner radius of the macOS artwork, as a fraction of its own width.
const _macosCornerFraction = 0.236;

/// Android density bucket to launcher icon size, in pixels.
const _androidDensities = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// Resolutions packed into every Windows `.ico`.
const _windowsIcoSizes = <int>[16, 20, 24, 32, 40, 48, 64, 128, 256];

/// Sizes of the installable web app icons.
const _webIconSizes = <int>[192, 512];

/// Size of the browser tab favicon.
const _faviconSize = 32;

/// Smallest square master the generator accepts.
///
/// The largest target is the 1024px store icon, so a smaller master would be
/// upscaled. Production must ship its current full-size artwork natively.
const _minimumMasterSize = 1024;

/// iOS `AppIcon.appiconset` slots: idiom, logical size, scale.
const _iosAppSlots = <(String, String, String)>[
  ('iphone', '20x20', '2x'),
  ('iphone', '20x20', '3x'),
  ('iphone', '29x29', '1x'),
  ('iphone', '29x29', '2x'),
  ('iphone', '29x29', '3x'),
  ('iphone', '40x40', '2x'),
  ('iphone', '40x40', '3x'),
  ('iphone', '60x60', '2x'),
  ('iphone', '60x60', '3x'),
  ('ipad', '20x20', '1x'),
  ('ipad', '20x20', '2x'),
  ('ipad', '29x29', '1x'),
  ('ipad', '29x29', '2x'),
  ('ipad', '40x40', '1x'),
  ('ipad', '40x40', '2x'),
  ('ipad', '76x76', '1x'),
  ('ipad', '76x76', '2x'),
  ('ipad', '83.5x83.5', '2x'),
  ('ios-marketing', '1024x1024', '1x'),
];

/// Watch `AppIcon.appiconset` slots: logical size, scale, role, subtype.
///
/// The last entry is the `watch-marketing` slot, which carries no role.
const _watchAppSlots = <(String, String, String?, String?)>[
  ('24x24', '2x', 'notificationCenter', '38mm'),
  ('27.5x27.5', '2x', 'notificationCenter', '42mm'),
  ('29x29', '2x', 'companionSettings', null),
  ('29x29', '3x', 'companionSettings', null),
  ('40x40', '2x', 'appLauncher', '38mm'),
  ('44x44', '2x', 'appLauncher', '40mm'),
  ('50x50', '2x', 'appLauncher', '44mm'),
  ('86x86', '2x', 'quickLook', '38mm'),
  ('98x98', '2x', 'quickLook', '42mm'),
  ('108x108', '2x', 'quickLook', '44mm'),
  ('1024x1024', '1x', null, null),
];

/// macOS `AppIcon.appiconset` slots: pixel size, logical size, scale.
const _macosAppSlots = <(int, String, String)>[
  (16, '16x16', '1x'),
  (32, '16x16', '2x'),
  (32, '32x32', '1x'),
  (64, '32x32', '2x'),
  (128, '128x128', '1x'),
  (256, '128x128', '2x'),
  (256, '256x256', '1x'),
  (512, '256x256', '2x'),
  (512, '512x512', '1x'),
  (1024, '512x512', '2x'),
];

void main(List<String> arguments) {
  final check = arguments.contains('--check');
  final unknown = arguments.where((a) => a != '--check').toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown argument(s): ${unknown.join(' ')}');
    stderr.writeln('usage: dart run tool/generate_app_icons.dart [--check]');
    exit(64);
  }

  if (!File('pubspec.yaml').existsSync() ||
      !Directory(_masterDirectory).existsSync()) {
    stderr.writeln(
      'Run this script from apps/flutter (expected $_masterDirectory and '
      'pubspec.yaml in ${Directory.current.path}).',
    );
    exit(66);
  }

  final masters = _loadMasters();
  final plan = _buildPlan(masters);

  if (check) {
    exit(_checkPlan(plan) ? 0 : 1);
  }

  var written = 0;
  var unchanged = 0;
  for (final output in plan.files) {
    final file = File(output.path);
    if (file.existsSync() && _sameBytes(file.readAsBytesSync(), output.bytes)) {
      unchanged++;
      continue;
    }
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(output.bytes);
    written++;
  }
  stdout.writeln(
    'Generated ${plan.files.length} icon assets '
    '($written written, $unchanged already current).',
  );
}

// ---------------------------------------------------------------------------
// Masters
// ---------------------------------------------------------------------------

/// Loads and validates the three master images.
Map<AppFlavor, img.Image> _loadMasters() {
  final masters = <AppFlavor, img.Image>{};
  for (final flavor in AppFlavor.values) {
    final path = '$_masterDirectory/pomodoist_icon_${flavor.name}.png';
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('Missing master image: $path');
      exit(66);
    }
    final decoded = img.decodePng(file.readAsBytesSync());
    if (decoded == null) {
      stderr.writeln('Not a PNG: $path');
      exit(66);
    }
    if (decoded.width != decoded.height) {
      stderr.writeln(
        'Master must be square: $path is ${decoded.width}x${decoded.height}.',
      );
      exit(66);
    }
    if (decoded.hasAlpha) {
      stderr.writeln('Master must be opaque: $path carries an alpha channel.');
      exit(66);
    }
    if (decoded.width < _minimumMasterSize) {
      stderr.writeln(
        'Master must be at least ${_minimumMasterSize}px so the '
        '${_minimumMasterSize}px store icon is never upscaled: $path is '
        '${decoded.width}px.',
      );
      exit(66);
    }
    masters[flavor] = decoded;
  }
  return masters;
}

// ---------------------------------------------------------------------------
// Plan
// ---------------------------------------------------------------------------

/// One image slot of an `.appiconset`, in the order Xcode writes its fields.
class _AssetSlot {
  _AssetSlot(this.fields) : fileName = fields['filename']! as String;

  final Map<String, Object> fields;
  final String fileName;

  /// The pixel edge length this slot needs.
  int get pixels =>
      (double.parse(_logicalSize(fields['size']! as String)) *
              double.parse((fields['scale']! as String).replaceAll('x', '')))
          .round();

  /// The slot identity `Contents.json` declares, ignoring the file name.
  String get identity => [
    for (final key in ['idiom', 'size', 'scale', 'role', 'subtype'])
      if (fields.containsKey(key)) '$key=${fields[key]}',
  ].join(' ');

  static String _logicalSize(String size) => size.split('x').first;
}

/// A single file the generator owns.
class _Output {
  _Output.png(this.path, this.bytes, this.pixels, this.alpha)
    : kind = _FileKind.png,
      icoSizes = null;

  _Output.ico(this.path, this.bytes, this.icoSizes)
    : kind = _FileKind.ico,
      pixels = null,
      alpha = null;

  _Output.json(this.path, this.bytes)
    : kind = _FileKind.json,
      pixels = null,
      alpha = null,
      icoSizes = null;

  final String path;
  final Uint8List bytes;
  final _FileKind kind;
  final int? pixels;
  final _AlphaPolicy? alpha;
  final List<int>? icoSizes;
}

enum _FileKind { png, ico, json }

enum _AlphaPolicy {
  /// The PNG must carry an alpha channel.
  alpha,

  /// The PNG must be fully opaque and carry no alpha channel.
  opaque,
}

/// Everything one run of the generator produces, plus what verification needs.
class _Plan {
  final List<_Output> files = [];

  /// Appiconset directory to the slots it must declare.
  final Map<String, List<_AssetSlot>> iconSets = {};

  /// Appiconset directories whose `Contents.json` this script writes.
  final Set<String> generatedContents = {};

  /// Web manifest path to the flavor it must describe.
  final Map<String, AppFlavor> manifests = {};

  /// Directories whose `.png` contents are fully owned by this script.
  final Set<String> managedDirectories = {};
}

_Plan _buildPlan(Map<AppFlavor, img.Image> masters) {
  final plan = _Plan();
  for (final flavor in AppFlavor.values) {
    final master = masters[flavor]!;
    _addAndroid(plan, flavor, master);
    _addAppleApp(plan, flavor, master);
    _addWatchApp(plan, flavor, master);
    _addMacos(plan, flavor, master);
    _addWindows(plan, flavor, master);
    _addWeb(plan, flavor, master);
  }
  return plan;
}

void _addAndroid(_Plan plan, AppFlavor flavor, img.Image master) {
  // Android launcher PNGs carry an alpha channel (fully opaque here, since the
  // artwork is full bleed) — that is how the launcher icons shipped before the
  // flavors existed, and the check enforces the same channel layout.
  _androidDensities.forEach((density, pixels) {
    final bytes = _png(_alpha(_resize(master, pixels)));
    final directory = 'android/app/src/${flavor.name}/res/mipmap-$density';
    plan.managedDirectories.add(directory);
    plan.files.add(
      _Output.png(
        '$directory/ic_launcher.png',
        bytes,
        pixels,
        _AlphaPolicy.alpha,
      ),
    );
    if (flavor.isProduction) {
      // `main` is the manifest the flavor source sets merge over, so it keeps a
      // copy of the production launcher for builds that pass no flavor.
      final mainDirectory = 'android/app/src/main/res/mipmap-$density';
      plan.managedDirectories.add(mainDirectory);
      plan.files.add(
        _Output.png(
          '$mainDirectory/ic_launcher.png',
          bytes,
          pixels,
          _AlphaPolicy.alpha,
        ),
      );
    }
  });
}

void _addAppleApp(_Plan plan, AppFlavor flavor, img.Image master) {
  final slots = [
    for (final (idiom, size, scale) in _iosAppSlots)
      _AssetSlot({
        'size': size,
        'idiom': idiom,
        'filename': 'Icon-App-$size@$scale.png',
        'scale': scale,
      }),
  ];
  _addAppIconSet(
    plan,
    flavor,
    'ios/Runner/Assets.xcassets/${_appIconSetName(flavor)}',
    slots,
    master,
    rounded: false,
  );
}

void _addWatchApp(_Plan plan, AppFlavor flavor, img.Image master) {
  final slots = [
    for (final (size, scale, role, subtype) in _watchAppSlots)
      _AssetSlot({
        'filename': 'Icon-App-$size@$scale.png',
        'idiom': size == '1024x1024' ? 'watch-marketing' : 'watch',
        'role': ?role,
        'scale': scale,
        'size': size,
        'subtype': ?subtype,
      }),
  ];
  _addAppIconSet(
    plan,
    flavor,
    'ios/PomodoistWatch/Assets.xcassets/${_appIconSetName(flavor)}',
    slots,
    master,
    rounded: false,
  );
}

void _addMacos(_Plan plan, AppFlavor flavor, img.Image master) {
  final slots = [
    for (final (pixels, size, scale) in _macosAppSlots)
      _AssetSlot({
        'size': size,
        'idiom': 'mac',
        'filename': 'app_icon_$pixels.png',
        'scale': scale,
      }),
  ];
  _addAppIconSet(
    plan,
    flavor,
    'macos/Runner/Assets.xcassets/${_appIconSetName(flavor)}',
    slots,
    master,
    rounded: true,
  );
}

/// Writes one appiconset: the unique PNGs it references, and — except for
/// production, whose `Contents.json` is Xcode-managed — the manifest itself.
void _addAppIconSet(
  _Plan plan,
  AppFlavor flavor,
  String directory,
  List<_AssetSlot> slots,
  img.Image master, {
  required bool rounded,
}) {
  plan.managedDirectories.add(directory);
  plan.iconSets[directory] = slots;

  final rendered = <int, Uint8List>{};
  for (final slot in slots) {
    final bytes = rendered.putIfAbsent(
      slot.pixels,
      () => _png(
        rounded
            ? _macosIcon(master, slot.pixels)
            : _opaque(_resize(master, slot.pixels)),
      ),
    );
    plan.files.add(
      _Output.png(
        '$directory/${slot.fileName}',
        bytes,
        slot.pixels,
        rounded ? _AlphaPolicy.alpha : _AlphaPolicy.opaque,
      ),
    );
  }

  if (!flavor.isProduction) {
    plan.generatedContents.add(directory);
    plan.files.add(
      _Output.json('$directory/Contents.json', _contentsJson(slots)),
    );
  }
}

void _addWindows(_Plan plan, AppFlavor flavor, img.Image master) {
  final name = flavor.isProduction
      ? 'app_icon.ico'
      : 'app_icon_${flavor.name}.ico';
  final directory = 'windows/runner/resources';
  plan.managedDirectories.add(directory);
  plan.files.add(
    _Output.ico(
      '$directory/$name',
      _encodeIco([
        for (final pixels in _windowsIcoSizes) _alpha(_resize(master, pixels)),
      ]),
      _windowsIcoSizes,
    ),
  );
}

void _addWeb(_Plan plan, AppFlavor flavor, img.Image master) {
  final directory = 'web/icons/${flavor.name}';
  plan.managedDirectories.add(directory);

  final icons = <int, Uint8List>{};
  for (final pixels in _webIconSizes) {
    final bytes = _png(_opaque(_resize(master, pixels)));
    icons[pixels] = bytes;
    plan.files.add(
      _Output.png(
        '$directory/Icon-$pixels.png',
        bytes,
        pixels,
        _AlphaPolicy.opaque,
      ),
    );
    // The maskable entries are copies of the plain icons, matching what the
    // repository shipped before the flavors existed.
    plan.files.add(
      _Output.png(
        '$directory/Icon-maskable-$pixels.png',
        bytes,
        pixels,
        _AlphaPolicy.opaque,
      ),
    );
  }

  final favicon = _png(_alpha(_resize(master, _faviconSize)));
  plan.files.add(
    _Output.png(
      '$directory/favicon.png',
      favicon,
      _faviconSize,
      _AlphaPolicy.alpha,
    ),
  );
  if (flavor.isProduction) {
    // `web/index.html` still points at the unversioned favicon.
    plan.files.add(
      _Output.png('web/favicon.png', favicon, _faviconSize, _AlphaPolicy.alpha),
    );
  }

  final manifestPath = flavor.isProduction
      ? 'web/manifest.json'
      : 'web/manifest-${flavor.name}.json';
  plan.manifests[manifestPath] = flavor;
  plan.files.add(_Output.json(manifestPath, _manifestJson(flavor)));
}

String _appIconSetName(AppFlavor flavor) {
  if (flavor.isProduction) return 'AppIcon.appiconset';
  final name = flavor.name;
  return 'AppIcon-${name[0].toUpperCase()}${name.substring(1)}.appiconset';
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// Resizes [master] to a square [pixels] image.
///
/// Box averaging is the only filter in `package:image` that samples the whole
/// source footprint of a destination pixel, which is what keeps the 1024px
/// store icon and the 16px favicon free of aliasing.
img.Image _resize(img.Image master, int pixels) => img.copyResize(
  master,
  width: pixels,
  height: pixels,
  interpolation: img.Interpolation.average,
);

img.Image _opaque(img.Image image) =>
    image.numChannels == 3 ? image : image.convert(numChannels: 3);

img.Image _alpha(img.Image image) =>
    image.numChannels == 4 ? image : image.convert(numChannels: 4);

/// Renders the macOS variant: the artwork inset in the canvas, corners rounded,
/// everything outside them transparent.
img.Image _macosIcon(img.Image master, int pixels) {
  final box = (pixels * _macosCanvasFraction).round();
  final art = _alpha(_resize(master, box));
  _roundCorners(art, box * _macosCornerFraction);

  final canvas = img.Image(width: pixels, height: pixels, numChannels: 4);
  final offset = (pixels - box) ~/ 2;
  img.compositeImage(canvas, art, dstX: offset, dstY: offset);
  return canvas;
}

/// Multiplies the alpha of [image] by rounded-rectangle coverage.
///
/// Straight edges land on pixel boundaries, so only the four corner quadrants
/// need antialiasing; they are supersampled 16x16, which resolves 257 coverage
/// levels and keeps the curve as smooth as the icon it replaces.
void _roundCorners(img.Image image, double radius) {
  const samples = 16;
  final size = image.width.toDouble();
  final innerMin = radius;
  final innerMax = size - radius;
  for (var y = 0; y < image.height; y++) {
    final dy = _cornerDistance(y + 0.5, innerMin, innerMax);
    for (var x = 0; x < image.width; x++) {
      final dx = _cornerDistance(x + 0.5, innerMin, innerMax);
      if (dx == 0 || dy == 0) continue;
      var inside = 0;
      for (var sy = 0; sy < samples; sy++) {
        for (var sx = 0; sx < samples; sx++) {
          final px = x + (sx + 0.5) / samples;
          final py = y + (sy + 0.5) / samples;
          final cx = _cornerDistance(px, innerMin, innerMax);
          final cy = _cornerDistance(py, innerMin, innerMax);
          if (cx * cx + cy * cy <= radius * radius) inside++;
        }
      }
      if (inside == samples * samples) continue;
      final pixel = image.getPixel(x, y);
      image.setPixelRgba(
        x,
        y,
        pixel.r,
        pixel.g,
        pixel.b,
        (pixel.a * inside / (samples * samples)).round(),
      );
    }
  }
}

/// Distance from [coordinate] to the straight run `[innerMin, innerMax]`, or 0
/// when it already lies inside it.
double _cornerDistance(double coordinate, double innerMin, double innerMax) =>
    math.max(innerMin - coordinate, 0) + math.max(coordinate - innerMax, 0);

Uint8List _png(img.Image image) => img.encodePng(image);

// ---------------------------------------------------------------------------
// Windows ICO
// ---------------------------------------------------------------------------

/// Packs [images] into a multi-resolution `.ico`.
///
/// Entries are PNG-compressed, which Windows has accepted since Vista and which
/// is what the repository shipped before the flavors existed. `package:image`
/// exposes only the single-image `encodeIco`, so the container is written here.
Uint8List _encodeIco(List<img.Image> images) {
  final payloads = [for (final image in images) _png(image)];
  var offset = 6 + images.length * 16;

  final out = BytesBuilder();
  out.add(_uint16(0)); // reserved
  out.add(_uint16(1)); // type: icon
  out.add(_uint16(images.length));

  for (var i = 0; i < images.length; i++) {
    final image = images[i];
    out.addByte(image.width >= 256 ? 0 : image.width);
    out.addByte(image.height >= 256 ? 0 : image.height);
    out.addByte(0); // palette size
    out.addByte(0); // reserved
    out.add(_uint16(1)); // colour planes
    out.add(_uint16(32)); // bits per pixel
    out.add(_uint32(payloads[i].length));
    out.add(_uint32(offset));
    offset += payloads[i].length;
  }
  for (final payload in payloads) {
    out.add(payload);
  }
  return out.takeBytes();
}

Uint8List _uint16(int value) =>
    Uint8List.fromList([value & 0xff, (value >> 8) & 0xff]);

Uint8List _uint32(int value) => Uint8List.fromList([
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
]);

// ---------------------------------------------------------------------------
// Metadata files
// ---------------------------------------------------------------------------

/// Renders an `.appiconset/Contents.json` in Xcode's layout.
Uint8List _contentsJson(List<_AssetSlot> slots) {
  final buffer = StringBuffer('{\n  "images" : [\n');
  for (var i = 0; i < slots.length; i++) {
    final fields = slots[i].fields;
    final keys = fields.keys.toList();
    buffer.writeln('    {');
    for (var k = 0; k < keys.length; k++) {
      final value = fields[keys[k]]!;
      final rendered = value is int ? '$value' : '"$value"';
      buffer.writeln(
        '      "${keys[k]}" : $rendered${k == keys.length - 1 ? '' : ','}',
      );
    }
    buffer.writeln(i == slots.length - 1 ? '    }' : '    },');
  }
  buffer
    ..writeln('  ],')
    ..writeln('  "info" : {')
    ..writeln('    "version" : 1,')
    ..writeln('    "author" : "xcode"')
    ..writeln('  }')
    ..writeln('}');
  return _utf8(buffer.toString());
}

/// Splash background behind the installed shortcut, matching the web loader's
/// light `--loader-background` in `web/index.html`.
const _webBackgroundColor = '#FFFDFB';

/// Brand accent from the `accent` token in `docs/design-system.md`.
const _webThemeColor = '#D83B2E';

const _webDescription =
    'Open-source task manager with a built-in Pomodoro focus timer.';

/// Renders a web app manifest in the shape `web/manifest.json` already has.
///
/// `start_url` stays `"."` for every flavor: the same web image is deployed to
/// each environment and reads its flavor from `config.js`, so an installed
/// shortcut must stay on the origin it was installed from.
Uint8List _manifestJson(AppFlavor flavor) {
  final icons = <Map<String, Object>>[
    for (final pixels in _webIconSizes)
      {
        'src': 'icons/${flavor.name}/Icon-$pixels.png',
        'sizes': '${pixels}x$pixels',
        'type': 'image/png',
      },
    for (final pixels in _webIconSizes)
      {
        'src': 'icons/${flavor.name}/Icon-maskable-$pixels.png',
        'sizes': '${pixels}x$pixels',
        'type': 'image/png',
        'purpose': 'maskable',
      },
  ];

  final manifest = <String, Object>{
    'name': flavor.displayName,
    'short_name': flavor.displayName,
    'start_url': '.',
    'display': 'standalone',
    'background_color': _webBackgroundColor,
    'theme_color': _webThemeColor,
    'description': _webDescription,
    'orientation': 'portrait-primary',
    'prefer_related_applications': false,
    'icons': icons,
  };
  return _utf8('${const JsonEncoder.withIndent('    ').convert(manifest)}\n');
}

Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Compares the committed tree against [plan] and validates every asset.
///
/// Returns true when the tree is exactly what the masters produce and every
/// asset satisfies its dimensions, format, alpha policy and slot contract.
bool _checkPlan(_Plan plan) {
  final problems = <String>[];

  for (final output in plan.files) {
    final file = File(output.path);
    if (!file.existsSync()) {
      problems.add('missing: ${output.path}');
      continue;
    }
    final bytes = file.readAsBytesSync();
    if (!_sameBytes(bytes, output.bytes)) {
      problems.add('stale: ${output.path}');
      continue;
    }
    problems.addAll(_validateFile(output, bytes));
  }

  for (final entry in plan.iconSets.entries) {
    problems.addAll(_validateContents(entry.key, entry.value));
  }

  for (final entry in plan.manifests.entries) {
    problems.addAll(_validateManifest(entry.key, entry.value));
  }

  for (final directory in plan.managedDirectories) {
    if (!Directory(directory).existsSync()) continue;
    final expected = {
      for (final output in plan.files)
        if (output.path.startsWith('$directory/'))
          output.path.substring(directory.length + 1),
    };
    for (final entity in Directory(directory).listSync()) {
      if (entity is! File || !entity.path.endsWith('.png')) continue;
      final name = entity.uri.pathSegments.last;
      if (!expected.contains(name)) {
        problems.add('unexpected: ${entity.path}');
      }
    }
  }

  if (problems.isEmpty) {
    stdout.writeln(
      'Checked ${plan.files.length} icon assets: all current and valid.',
    );
    return true;
  }

  stderr.writeln(
    'Icon assets are out of date (${problems.length} problem(s)):',
  );
  for (final problem in problems) {
    stderr.writeln('  $problem');
  }
  stderr.writeln('Run: dart run tool/generate_app_icons.dart');
  return false;
}

/// Validates one on-disk file against the format it must be in.
List<String> _validateFile(_Output output, Uint8List bytes) {
  switch (output.kind) {
    case _FileKind.png:
      final decoded = img.decodePng(bytes);
      if (decoded == null) return ['not a PNG: ${output.path}'];
      final problems = <String>[];
      final pixels = output.pixels!;
      if (decoded.width != pixels || decoded.height != pixels) {
        problems.add(
          'wrong size: ${output.path} is ${decoded.width}x${decoded.height}, '
          'expected ${pixels}x$pixels',
        );
      }
      if (output.alpha == _AlphaPolicy.alpha && !decoded.hasAlpha) {
        problems.add('missing alpha channel: ${output.path}');
      }
      if (output.alpha == _AlphaPolicy.opaque && decoded.hasAlpha) {
        problems.add('unexpected alpha channel: ${output.path}');
      }
      return problems;

    case _FileKind.ico:
      return _validateIco(output, bytes);

    case _FileKind.json:
      return const [];
  }
}

/// Validates the ICO container: entry count, sizes, 32bpp PNG payloads.
List<String> _validateIco(_Output output, Uint8List bytes) {
  final expected = output.icoSizes!;
  if (bytes.length < 6) return ['truncated ICO: ${output.path}'];
  final view = ByteData.sublistView(bytes);
  if (view.getUint16(0, Endian.little) != 0 ||
      view.getUint16(2, Endian.little) != 1) {
    return ['not an ICO: ${output.path}'];
  }
  final count = view.getUint16(4, Endian.little);
  if (count != expected.length) {
    return [
      'wrong ICO entry count: ${output.path} has $count, expected '
          '${expected.length}',
    ];
  }
  final problems = <String>[];
  for (var i = 0; i < count; i++) {
    final base = 6 + i * 16;
    final width = view.getUint8(base) == 0 ? 256 : view.getUint8(base);
    final height = view.getUint8(base + 1) == 0 ? 256 : view.getUint8(base + 1);
    final bits = view.getUint16(base + 6, Endian.little);
    final length = view.getUint32(base + 8, Endian.little);
    final offset = view.getUint32(base + 12, Endian.little);
    if (width != expected[i] || height != expected[i]) {
      problems.add(
        'wrong ICO slot $i in ${output.path}: ${width}x$height, expected '
        '${expected[i]}',
      );
      continue;
    }
    if (bits != 32) {
      problems.add('ICO slot $i in ${output.path} is $bits bpp, expected 32');
    }
    if (offset + length > bytes.length) {
      problems.add('ICO slot $i in ${output.path} runs past end of file');
      continue;
    }
    final payload = img.decodePng(bytes.sublist(offset, offset + length));
    if (payload == null ||
        payload.width != expected[i] ||
        payload.height != expected[i]) {
      problems.add(
        'ICO slot $i in ${output.path} is not a ${expected[i]}px PNG',
      );
    }
  }
  return problems;
}

/// Validates an `.appiconset/Contents.json` against the required slots.
///
/// This covers production too, whose `Contents.json` is Xcode-managed and never
/// rewritten by the generator.
List<String> _validateContents(String directory, List<_AssetSlot> slots) {
  final path = '$directory/Contents.json';
  final file = File(path);
  if (!file.existsSync()) return ['missing: $path'];

  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    return ['invalid JSON in $path: ${error.message}'];
  }
  if (decoded is! Map<String, Object?> || decoded['images'] is! List) {
    return ['invalid appiconset in $path: no images array'];
  }

  final declared = <String, String>{};
  for (final entry in decoded['images']! as List) {
    if (entry is! Map<String, Object?>) continue;
    final fields = <String, Object>{
      for (final key in ['idiom', 'size', 'scale', 'role', 'subtype'])
        if (entry[key] != null) key: entry[key]!,
    };
    declared[_AssetSlot({
          ...fields,
          'filename': entry['filename'] ?? '',
        }).identity] =
        entry['filename']! as String;
  }

  final problems = <String>[];
  for (final slot in slots) {
    final fileName = declared[slot.identity];
    if (fileName == null) {
      problems.add('missing slot in $path: ${slot.identity}');
      continue;
    }
    final asset = File('$directory/$fileName');
    if (!asset.existsSync()) {
      problems.add('missing asset referenced by $path: $fileName');
      continue;
    }
    final decodedAsset = img.decodePng(asset.readAsBytesSync());
    if (decodedAsset == null) {
      problems.add('not a PNG: $directory/$fileName');
    } else if (decodedAsset.width != slot.pixels ||
        decodedAsset.height != slot.pixels) {
      problems.add(
        'wrong size: $directory/$fileName is '
        '${decodedAsset.width}x${decodedAsset.height}, expected '
        '${slot.pixels}x${slot.pixels}',
      );
    }
  }
  if (declared.length != slots.length) {
    problems.add(
      '$path declares ${declared.length} slots, expected ${slots.length}',
    );
  }
  return problems;
}

/// Validates a web manifest's identity and that every icon it names exists at
/// the size it claims.
List<String> _validateManifest(String path, AppFlavor flavor) {
  final file = File(path);
  if (!file.existsSync()) return ['missing: $path'];

  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    return ['invalid JSON in $path: ${error.message}'];
  }
  if (decoded is! Map<String, Object?>) return ['invalid manifest: $path'];

  final problems = <String>[];
  for (final key in [
    'name',
    'short_name',
    'start_url',
    'display',
    'background_color',
    'theme_color',
    'description',
    'orientation',
    'prefer_related_applications',
    'icons',
  ]) {
    if (!decoded.containsKey(key)) problems.add('$path is missing "$key"');
  }
  if (decoded['name'] != flavor.displayName) {
    problems.add(
      '$path name is "${decoded['name']}", expected "${flavor.displayName}"',
    );
  }
  if (decoded['short_name'] != flavor.displayName) {
    problems.add(
      '$path short_name is "${decoded['short_name']}", expected '
      '"${flavor.displayName}"',
    );
  }
  if (decoded['start_url'] != '.') {
    problems.add('$path start_url is "${decoded['start_url']}", expected "."');
  }

  final icons = decoded['icons'];
  if (icons is! List || icons.isEmpty) {
    problems.add('$path declares no icons');
    return problems;
  }
  for (final entry in icons) {
    if (entry is! Map<String, Object?>) continue;
    final src = entry['src'];
    final sizes = entry['sizes'];
    if (src is! String || sizes is! String) {
      problems.add('$path has an icon without src/sizes');
      continue;
    }
    final asset = File('web/$src');
    if (!asset.existsSync()) {
      problems.add('$path references missing icon web/$src');
      continue;
    }
    final decodedAsset = img.decodePng(asset.readAsBytesSync());
    final expected = sizes.split('x').first;
    if (decodedAsset == null ||
        '${decodedAsset.width}' != expected ||
        '${decodedAsset.height}' != expected) {
      problems.add('$path icon web/$src is not ${sizes}px');
    }
  }
  return problems;
}
