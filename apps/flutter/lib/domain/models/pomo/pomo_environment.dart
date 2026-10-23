/// The native logical-pixel coordinate system used by the companion host.
class PomoDisplay {
  const PomoDisplay({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.workX,
    required this.workY,
    required this.workWidth,
    required this.workHeight,
    this.scale = 1,
  });

  final String id, name;
  final double x, y, width, height, workX, workY, workWidth, workHeight, scale;

  bool contains(double px, double py) =>
      px >= x && py >= y && px < x + width && py < y + height;
}

enum PomoFollowSource { cursor, workspace, none }

enum PomoPlacementBackend { unknown, x11, layerShell, gnomeShell }

enum PomoGnomeExtensionState {
  notInstalled,
  disabled,
  reloginRequired,
  active,
  incompatible,
  error,
}

enum PomoGnomeExtensionAction { install, enable, update }

class PomoEnvironment {
  const PomoEnvironment({
    this.checking = true,
    this.available = false,
    this.backend = '',
    this.placementBackend = PomoPlacementBackend.unknown,
    this.gnomeExtensionState,
    this.gnomeExtensionVersion,
    this.gnomeShellVersion,
    this.gnomeExtensionError,
    this.desktop = '',
    this.sessionType = '',
    this.distribution = '',
    this.reason,
    this.followSource = PomoFollowSource.none,
    this.displays = const [],
    this.primaryDisplayId,
    this.userDisplayId,
  });

  final bool checking, available;
  final String backend, desktop, sessionType, distribution;
  final String? reason;
  final PomoPlacementBackend placementBackend;
  final PomoGnomeExtensionState? gnomeExtensionState;
  final int? gnomeExtensionVersion;
  final String? gnomeShellVersion, gnomeExtensionError;
  bool get usesGnomeShell =>
      placementBackend == PomoPlacementBackend.gnomeShell;
  bool get gnomeXWaylandUnavailable =>
      usesGnomeShell && reason == 'gnomeXWaylandUnavailable';
  bool get gnomeUserExtensionsDisabled =>
      usesGnomeShell && reason == 'gnomeUserExtensionsDisabled';
  bool get _gnomeExtensionNeedsUpdate =>
      gnomeExtensionVersion != null && gnomeExtensionVersion != 1;
  PomoGnomeExtensionAction? get gnomeExtensionAction {
    if (!usesGnomeShell ||
        gnomeXWaylandUnavailable ||
        gnomeUserExtensionsDisabled ||
        gnomeExtensionState == PomoGnomeExtensionState.reloginRequired) {
      return null;
    }
    if (gnomeExtensionState == PomoGnomeExtensionState.notInstalled) {
      return PomoGnomeExtensionAction.install;
    }
    if (_gnomeExtensionNeedsUpdate) return PomoGnomeExtensionAction.update;
    if (gnomeExtensionState == PomoGnomeExtensionState.disabled) {
      return PomoGnomeExtensionAction.enable;
    }
    return null;
  }

  final PomoFollowSource followSource;
  final List<PomoDisplay> displays;
  final String? primaryDisplayId, userDisplayId;
  bool get canFollow => followSource != PomoFollowSource.none;

  PomoEnvironment copyWith({
    bool? checking,
    bool? available,
    String? backend,
    PomoPlacementBackend? placementBackend,
    PomoGnomeExtensionState? gnomeExtensionState,
    int? gnomeExtensionVersion,
    String? gnomeShellVersion,
    String? gnomeExtensionError,
    String? desktop,
    String? sessionType,
    String? distribution,
    String? reason,
    PomoFollowSource? followSource,
    List<PomoDisplay>? displays,
    String? primaryDisplayId,
    String? userDisplayId,
    bool clearReason = false,
    bool clearUserDisplay = false,
  }) => PomoEnvironment(
    checking: checking ?? this.checking,
    available: available ?? this.available,
    backend: backend ?? this.backend,
    placementBackend: placementBackend ?? this.placementBackend,
    gnomeExtensionState: gnomeExtensionState ?? this.gnomeExtensionState,
    gnomeExtensionVersion: gnomeExtensionVersion ?? this.gnomeExtensionVersion,
    gnomeShellVersion: gnomeShellVersion ?? this.gnomeShellVersion,
    gnomeExtensionError: gnomeExtensionError ?? this.gnomeExtensionError,
    desktop: desktop ?? this.desktop,
    sessionType: sessionType ?? this.sessionType,
    distribution: distribution ?? this.distribution,
    reason: clearReason ? null : reason ?? this.reason,
    followSource: followSource ?? this.followSource,
    displays: displays == null ? this.displays : List.unmodifiable(displays),
    primaryDisplayId: primaryDisplayId ?? this.primaryDisplayId,
    userDisplayId: clearUserDisplay
        ? null
        : userDisplayId ?? this.userDisplayId,
  );
}

String buildPomoSupportDetails(
  PomoEnvironment environment,
  String appVersion,
) =>
    'Pomo Linux environment\n'
    'Support: support@pomodoist.com\n'
    'Desktop: ${environment.desktop}\n'
    'Session: ${environment.sessionType}\n'
    'Backend: ${environment.backend}\n'
    'Placement backend: ${environment.placementBackend.name}\n'
    'GNOME Shell: ${environment.gnomeShellVersion ?? 'unknown'}\n'
    'GNOME extension: ${environment.gnomeExtensionState?.name ?? 'not applicable'} '
    '(version ${environment.gnomeExtensionVersion ?? 'unknown'})\n'
    'Distribution: ${environment.distribution}\n'
    'App version: $appVersion\n';

/// Opens a draft in the user's mail application; this helper never sends mail.
Uri buildPomoSupportUri(PomoEnvironment environment, String appVersion) => Uri(
  scheme: 'mailto',
  path: 'support@pomodoist.com',
  query:
      'subject=${Uri.encodeComponent('Pomo Linux support')}'
      '&body=${Uri.encodeComponent(buildPomoSupportDetails(environment, appVersion))}',
);
