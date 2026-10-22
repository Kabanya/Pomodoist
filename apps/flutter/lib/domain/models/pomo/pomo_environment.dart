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

class PomoEnvironment {
  const PomoEnvironment({
    this.checking = true,
    this.available = false,
    this.backend = '',
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
  final PomoFollowSource followSource;
  final List<PomoDisplay> displays;
  final String? primaryDisplayId, userDisplayId;
  bool get canFollow => followSource != PomoFollowSource.none;

  PomoEnvironment copyWith({
    bool? checking,
    bool? available,
    String? backend,
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
