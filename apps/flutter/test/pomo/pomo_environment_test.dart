import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_environment_codec.dart';
import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';
import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

Map<String, Object?> environmentPayload({String backend = 'x11'}) => {
  'available': true,
  'backend': backend,
  'desktop': 'KDE',
  'sessionType': 'wayland',
  'distribution': 'Fedora',
  'followSource': 'cursor',
  'primaryDisplayId': 'native-left',
  'displays': [
    {
      'id': 'native-left',
      'name': 'HDMI-A-1',
      'x': -1920,
      'y': 0,
      'width': 1920,
      'height': 1080,
      'workY': 30,
      'workHeight': 1050,
    },
    {
      'id': 'native-right',
      'name': 'DP-1',
      'x': 0,
      'y': 0,
      'width': 2560,
      'height': 1440,
      'scale': 1.5,
    },
  ],
};

void main() {
  test('defaults keep environment checking and unavailable', () {
    const environment = PomoEnvironment();
    expect(environment.checking, isTrue);
    expect(environment.available, isFalse);
    expect(environment.canFollow, isFalse);
  });

  test('native logical geometry and capabilities parse safely', () {
    final environment = parsePomoEnvironment(environmentPayload());
    expect(environment.available, isTrue);
    expect(environment.checking, isFalse);
    expect(environment.canFollow, isTrue);
    expect(environment.primaryDisplayId, 'native-left');
    expect(environment.displays.first.workY, 30);
    expect(environment.displays.first.workWidth, 1920);
    expect(environment.displays.last.scale, 1.5);
    expect(() => environment.displays.clear(), throwsUnsupportedError);
  });

  test(
    'GNOME states retain bridge diagnostics without changing actual backend',
    () {
      final raw = environmentPayload()
        ..addAll({
          'placementBackend': 'gnomeShell',
          'gnomeExtensionState': 'reloginRequired',
          'gnomeExtensionVersion': 1,
          'gnomeShellVersion': '50.2',
          'gnomeExtensionError': 'Loaded version is stale',
          'available': false,
        });
      final environment = parsePomoEnvironment(raw);
      expect(environment.backend, 'x11');
      expect(environment.placementBackend, PomoPlacementBackend.gnomeShell);
      expect(
        environment.gnomeExtensionState,
        PomoGnomeExtensionState.reloginRequired,
      );
      expect(environment.gnomeExtensionVersion, 1);
      expect(environment.gnomeShellVersion, '50.2');
      expect(environment.gnomeExtensionError, 'Loaded version is stale');
      expect(environment.available, false);
      final copied = environment.copyWith(userDisplayId: 'native-left');
      expect(
        copied.gnomeExtensionState,
        PomoGnomeExtensionState.reloginRequired,
      );
      expect(copied.gnomeExtensionVersion, 1);
      expect(
        buildPomoSupportDetails(copied, '1'),
        contains('Placement backend: gnomeShell'),
      );
      expect(
        buildPomoSupportDetails(copied, '1'),
        contains('GNOME extension: reloginRequired (version 1)'),
      );
    },
  );

  test('GNOME offers only the action appropriate to extension state', () {
    for (final (state, version, action) in [
      ('notInstalled', null, PomoGnomeExtensionAction.install),
      ('disabled', 1, PomoGnomeExtensionAction.enable),
      ('incompatible', 0, PomoGnomeExtensionAction.update),
      ('incompatible', 1, null),
      ('reloginRequired', 0, null),
      ('error', 1, null),
      ('active', 1, null),
    ]) {
      final environment = parsePomoEnvironment(
        environmentPayload()..addAll({
          'placementBackend': 'gnomeShell',
          'gnomeExtensionState': state,
          'gnomeExtensionVersion': version,
        }),
      );
      expect(environment.gnomeExtensionAction, action, reason: state);
      expect(environment.available, state == 'active', reason: state);
    }
  });

  test(
    'legacy environment maps infer existing placement and omit GNOME actions',
    () {
      final x11 = parsePomoEnvironment(environmentPayload());
      final wayland = parsePomoEnvironment(
        environmentPayload(backend: 'wayland'),
      );
      expect(x11.placementBackend, PomoPlacementBackend.x11);
      expect(wayland.placementBackend, PomoPlacementBackend.layerShell);
      expect(x11.gnomeExtensionState, isNull);
      final unknown = parsePomoEnvironment(
        environmentPayload()..addAll({
          'placementBackend': 'future',
          'gnomeExtensionState': 'future',
          'gnomeExtensionVersion': -4,
        }),
      );
      expect(unknown.placementBackend, PomoPlacementBackend.unknown);
      expect(unknown.gnomeExtensionState, PomoGnomeExtensionState.error);
      expect(unknown.gnomeExtensionVersion, isNull);
    },
  );

  test('missing XWayland cannot be repaired by installing the extension', () {
    final environment = parsePomoEnvironment(
      environmentPayload()..addAll({
        'placementBackend': 'gnomeShell',
        'gnomeExtensionState': 'notInstalled',
        'reason': 'gnomeXWaylandUnavailable',
        'available': false,
      }),
    );
    expect(environment.gnomeExtensionAction, isNull);
    expect(environment.gnomeXWaylandUnavailable, true);
  });

  test(
    'global user-extension disable blocks install, enable and update actions',
    () {
      for (final state in ['notInstalled', 'disabled', 'incompatible']) {
        final environment = parsePomoEnvironment(
          environmentPayload()..addAll({
            'placementBackend': 'gnomeShell',
            'gnomeExtensionState': state,
            'gnomeExtensionVersion': 0,
            'reason': 'gnomeUserExtensionsDisabled',
            'available': false,
          }),
        );
        expect(environment.gnomeExtensionAction, isNull, reason: state);
        expect(environment.gnomeUserExtensionsDisabled, true);
      }
    },
  );

  test('malformed native payloads fail closed', () {
    for (final raw in [
      null,
      4,
      'x11',
      [],
      {'available': true},
      {
        'displays': [
          null,
          {},
          {'id': 'bad', 'x': 0, 'y': 0, 'width': double.nan, 'height': 100},
        ],
      },
    ]) {
      final environment = parsePomoEnvironment(raw);
      expect(environment.available, isFalse);
      expect(environment.checking, isFalse);
      expect(environment.displays, isEmpty);
    }
  });

  test('invalid optional values and unknown identities fall back', () {
    final raw = environmentPayload();
    raw['primaryDisplayId'] = 'removed';
    raw['userDisplayId'] = 'removed';
    raw['followSource'] = 'pretend-cursor';
    (raw['displays'] as List).add({
      'id': 'native-right',
      'x': 0,
      'y': 0,
      'width': 100,
      'height': 100,
    });
    final environment = parsePomoEnvironment(raw);
    expect(environment.primaryDisplayId, 'native-left');
    expect(environment.userDisplayId, isNull);
    expect(environment.followSource, PomoFollowSource.none);
    expect(environment.displays.length, 2);
  });

  test('cursor edges map to actual native IDs including negative origins', () {
    final displays = parsePomoEnvironment(environmentPayload()).displays;
    expect(
      mapPomoMonitor(
        const PomoMonitorSample(cursorX: -1, cursorY: 400),
        displays,
      ),
      'native-left',
    );
    expect(
      mapPomoMonitor(
        const PomoMonitorSample(cursorX: 0, cursorY: 400),
        displays,
      ),
      'native-right',
    );
    expect(
      mapPomoMonitor(
        const PomoMonitorSample(cursorX: 2560, cursorY: 0),
        displays,
      ),
      isNull,
    );
  });

  test(
    'compositor names and geometry map to native IDs without inventing IDs',
    () {
      final displays = parsePomoEnvironment(environmentPayload()).displays;
      expect(
        mapPomoMonitor(const PomoMonitorSample(name: 'DP-1'), displays),
        'native-right',
      );
      expect(
        mapPomoMonitor(
          const PomoMonitorSample(
            name: 'compositor-43',
            x: -1920,
            y: 0,
            width: 1920,
            height: 1080,
          ),
          displays,
        ),
        'native-left',
      );
      expect(
        mapPomoMonitor(
          const PomoMonitorSample(name: 'compositor-43'),
          displays,
        ),
        isNull,
      );
    },
  );

  test(
    'mail support draft encodes Unicode and only approved environment fields',
    () {
      const environment = PomoEnvironment(
        backend: 'wayland & X',
        desktop: 'KDE / Плазма',
        sessionType: 'wayland',
        distribution: 'NixOS #1',
        reason: '/tmp/private-diagnostics/secret',
        userDisplayId: 'private-monitor',
      );
      final uri = buildPomoSupportUri(environment, '1.2.3+4');
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'support@pomodoist.com');
      expect(uri.queryParameters['subject'], 'Pomo Linux support');
      final details = buildPomoSupportDetails(environment, '1.2.3+4');
      expect(uri.queryParameters['body'], details);
      expect(details, contains('Desktop: KDE / Плазма\n'));
      expect(details, contains('Backend: wayland & X\n'));
      expect(details, contains('Distribution: NixOS #1\n'));
      expect(details, contains('App version: 1.2.3+4\n'));
      expect(details, isNot(contains('private')));
      expect(uri.toString(), contains('%D0'));
      expect(uri.fragment, isEmpty);
    },
  );
  test(
    'copied diagnostics include the support address without a mail client',
    () {
      expect(
        buildPomoSupportDetails(const PomoEnvironment(), '1.0'),
        contains('support@pomodoist.com'),
      );
    },
  );
}
