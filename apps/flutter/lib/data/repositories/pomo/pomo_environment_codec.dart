import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';
import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

double? pomoFiniteNumber(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

PomoEnvironment parsePomoEnvironment(Object? value) {
  if (value is! Map) {
    return const PomoEnvironment(
      checking: false,
      reason: 'The desktop did not return environment information.',
    );
  }
  String string(String key) => value[key] is String ? value[key] as String : '';
  final displays = <PomoDisplay>[];
  final ids = <String>{};
  final rawDisplays = value['displays'];
  if (rawDisplays is List) {
    for (final raw in rawDisplays) {
      if (raw is! Map || raw['id'] is! String) continue;
      final id = raw['id'] as String;
      final x = pomoFiniteNumber(raw['x']), y = pomoFiniteNumber(raw['y']);
      final w = pomoFiniteNumber(raw['width']);
      final h = pomoFiniteNumber(raw['height']);
      if (id.isEmpty ||
          ids.contains(id) ||
          x == null ||
          y == null ||
          w == null ||
          h == null ||
          w <= 0 ||
          h <= 0) {
        continue;
      }
      ids.add(id);
      final scale = pomoFiniteNumber(raw['scale']);
      final workWidth = pomoFiniteNumber(raw['workWidth']);
      final workHeight = pomoFiniteNumber(raw['workHeight']);
      displays.add(
        PomoDisplay(
          id: id,
          name: raw['name'] is String ? raw['name'] as String : id,
          x: x,
          y: y,
          width: w,
          height: h,
          workX: pomoFiniteNumber(raw['workX']) ?? x,
          workY: pomoFiniteNumber(raw['workY']) ?? y,
          workWidth: workWidth != null && workWidth > 0 ? workWidth : w,
          workHeight: workHeight != null && workHeight > 0 ? workHeight : h,
          scale: scale != null && scale > 0 ? scale : 1,
        ),
      );
    }
  }
  String? knownId(Object? candidate) =>
      candidate is String && ids.contains(candidate) ? candidate : null;
  final source = switch (value['followSource']) {
    'cursor' => PomoFollowSource.cursor,
    'workspace' => PomoFollowSource.workspace,
    _ => PomoFollowSource.none,
  };
  return PomoEnvironment(
    checking: false,
    available:
        value['available'] == true &&
        displays.isNotEmpty &&
        (value['placementBackend'] != 'gnomeShell' ||
            value['gnomeExtensionState'] == 'active'),
    backend: string('backend'),
    placementBackend: switch (value['placementBackend']) {
      'x11' => PomoPlacementBackend.x11,
      'layerShell' => PomoPlacementBackend.layerShell,
      'gnomeShell' => PomoPlacementBackend.gnomeShell,
      null => switch (string('backend').toLowerCase()) {
        'x11' => PomoPlacementBackend.x11,
        'wayland' => PomoPlacementBackend.layerShell,
        _ => PomoPlacementBackend.unknown,
      },
      _ => PomoPlacementBackend.unknown,
    },
    gnomeExtensionState: switch (value['gnomeExtensionState']) {
      null => null,
      'notInstalled' => PomoGnomeExtensionState.notInstalled,
      'disabled' => PomoGnomeExtensionState.disabled,
      'reloginRequired' => PomoGnomeExtensionState.reloginRequired,
      'active' => PomoGnomeExtensionState.active,
      'incompatible' => PomoGnomeExtensionState.incompatible,
      _ => PomoGnomeExtensionState.error,
    },
    gnomeExtensionVersion:
        value['gnomeExtensionVersion'] is int &&
            (value['gnomeExtensionVersion'] as int) >= 0
        ? value['gnomeExtensionVersion'] as int
        : null,
    gnomeShellVersion: value['gnomeShellVersion'] is String
        ? value['gnomeShellVersion'] as String
        : null,
    gnomeExtensionError: value['gnomeExtensionError'] is String
        ? value['gnomeExtensionError'] as String
        : null,
    desktop: string('desktop'),
    sessionType: string('sessionType'),
    distribution: string('distribution'),
    reason: value['reason'] is String ? value['reason'] as String : null,
    followSource: source,
    displays: List.unmodifiable(displays),
    primaryDisplayId:
        knownId(value['primaryDisplayId']) ??
        (displays.isEmpty ? null : displays.first.id),
    userDisplayId: knownId(value['userDisplayId']),
  );
}

/// Never invents a native display ID from a compositor's private output ID.
String? mapPomoMonitor(PomoMonitorSample sample, List<PomoDisplay> displays) {
  if (sample.cursorX != null && sample.cursorY != null) {
    for (final display in displays) {
      if (display.contains(sample.cursorX!, sample.cursorY!)) return display.id;
    }
  }
  final named = displays
      .where(
        (d) =>
            sample.name != null &&
            (d.name == sample.name || d.id == sample.name),
      )
      .toList();
  if (named.length == 1) return named.single.id;
  bool near(double? a, double b) => a != null && (a - b).abs() <= 2;
  final geometric = displays
      .where(
        (d) =>
            near(sample.x, d.x) &&
            near(sample.y, d.y) &&
            near(sample.width, d.width) &&
            near(sample.height, d.height),
      )
      .toList();
  return geometric.length == 1 ? geometric.single.id : null;
}
