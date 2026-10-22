import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';
import 'package:pomodoist/data/services/platform/pomo_follow_transport_io.dart';
import 'package:pomodoist/data/services/platform/pomo_kwin_follow_service.dart';
import 'package:pomodoist/data/services/platform/pomo_sway_follow_service.dart';
import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

class TestSwayConnection implements PomoSwayConnection {
  final events = StreamController<List<int>>(sync: true);
  final sent = <List<int>>[];
  bool closed = false;
  @override
  Stream<List<int>> get messages => events.stream;
  @override
  Future<void> send(List<int> bytes) async {
    sent.add(bytes);
    final frame = encodePomoSwayMessage(2, '{"success":true}');
    events.add(frame.sublist(0, 9));
    events.add(frame.sublist(9));
  }

  void emit(int type, String body) =>
      events.add(encodePomoSwayMessage(type, body));
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

Future<void> settleEvents() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'KWin Plasma 6 script path and interface match the exported adaptor',
    () {
      expect(pomoKwinScriptPath(0).value, '/Scripting/Script0');
      expect(pomoKwinScriptPath(42).value, '/Scripting/Script42');
      expect(pomoKwinScriptInterface, 'org.kde.kwin.Script');
    },
  );

  test('Hyprland transforms physical modes into logical output geometry', () {
    final output = parseHyprlandPomoOutput({
      'name': 'DP-2',
      'x': -1440,
      'y': 0,
      'width': 3840,
      'height': 2160,
      'scale': 1.5,
      'transform': 1,
    });
    expect(output!.width, 1440);
    expect(output.height, 2560);
    expect(output.x, -1440);
    expect(
      parseHyprlandPomoOutput({
        'x': 0,
        'y': 0,
        'width': 1,
        'height': 2,
        'scale': 0,
      }),
      isNull,
    );
    expect(
      parseSwayPomoOutput({
        'active': false,
        'rect': {'x': 0, 'y': 0, 'width': 1, 'height': 2},
      }),
      isNull,
    );
  });

  test('Hyprland read-only socket requests run only while following', () async {
    final requests = <String>[];
    final transport = LinuxPomoFollowTransport(
      environment: {
        'HYPRLAND_INSTANCE_SIGNATURE': 'instance_1',
        'XDG_RUNTIME_DIR': '/run/user/1000',
      },
      request: (path, request, type) async {
        expect(type, isNull);
        requests.add(request);
        if (request == 'j/monitors') {
          return [
            {
              'name': 'DP-1',
              'x': 0,
              'y': 0,
              'width': 1920,
              'height': 1080,
              'scale': 1,
            },
          ];
        }
        return {'x': 100, 'y': 200};
      },
    );
    const environment = PomoEnvironment(
      backend: 'wayland',
      desktop: 'Hyprland',
      followSource: PomoFollowSource.cursor,
    );
    expect(await transport.probe(environment), PomoFollowSource.cursor);
    expect(requests, ['j/monitors']);
    expect(await transport.sample(), isNull);
    await transport.start(environment, (_) {}, () {});
    expect((await transport.sample())!.name, 'DP-1');
    await transport.stop();
    expect(await transport.sample(), isNull);
    expect(requests, ['j/monitors', 'j/cursorpos']);
    transport.dispose();
  });

  test(
    'Sway pushes initial snapshot and workspace/output events without polling',
    () async {
      final connection = TestSwayConnection();
      final queries = <int?>[];
      var output = 'HDMI-A-1';
      var width = 1920;
      final samples = <PomoMonitorSample>[];
      final transport = LinuxPomoFollowTransport(
        environment: {'SWAYSOCK': '/tmp/sway-test.sock'},
        swayConnect: (_) async => connection,
        request: (path, request, type) async {
          queries.add(type);
          return type == 3
              ? [
                  {
                    'name': output,
                    'active': true,
                    'rect': {'x': 1920, 'y': 0, 'width': width, 'height': 1080},
                  },
                ]
              : [
                  {'focused': true, 'visible': true, 'output': output},
                ];
        },
      );
      const environment = PomoEnvironment(
        backend: 'wayland',
        desktop: 'sway',
        followSource: PomoFollowSource.workspace,
      );
      expect(await transport.probe(environment), PomoFollowSource.workspace);
      await transport.start(environment, samples.add, () {});
      expect(samples.single.name, 'HDMI-A-1');
      final subscription = connection.sent.single;
      expect(jsonDecode(utf8.decode(subscription.sublist(14))), [
        'workspace',
        'output',
      ]);
      expect(
        ByteData.sublistView(
          Uint8List.fromList(subscription),
          10,
          14,
        ).getUint32(0, Endian.little),
        2,
      );
      final before = queries.length;
      for (var i = 0; i < 10; ++i) {
        expect(await transport.sample(), isNull);
      }
      expect(await transport.probe(environment), PomoFollowSource.workspace);
      expect(queries.length, before);
      output = 'DP-1';
      connection.emit(0x80000000, '{"change":"focus","current":null}');
      await settleEvents();
      expect(samples.last.name, 'DP-1');
      width = 2560;
      connection.emit(0x80000001, '{"change":"unspecified"}');
      await settleEvents();
      expect(samples.last.width, 2560);
      expect(samples.last.cursorX, isNull);
      await transport.stop();
      expect(connection.closed, isTrue);
      final after = queries.length;
      expect(await transport.sample(), isNull);
      expect(queries.length, after);
      transport.dispose();
    },
  );

  test(
    'Sway disconnect closes its subscription and reconnect takes a new snapshot',
    () async {
      final first = TestSwayConnection(), second = TestSwayConnection();
      final connections = [first, second].iterator;
      var output = 'DP-1';
      var disconnects = 0;
      final samples = <PomoMonitorSample>[];
      final service = PomoSwayFollowService(
        connect: (_) async {
          connections.moveNext();
          return connections.current;
        },
        request: (path, request, type) async => type == 3
            ? [
                {
                  'name': output,
                  'active': true,
                  'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
                },
              ]
            : [
                {'focused': true, 'output': output},
              ],
      );
      await service.start('/tmp/sway.sock', samples.add, () => ++disconnects);
      await first.events.close();
      await settleEvents();
      expect(disconnects, 1);
      expect(service.running, isFalse);
      expect(first.closed, isTrue);
      output = 'DP-2';
      await service.start('/tmp/sway.sock', samples.add, () => ++disconnects);
      expect(service.running, isTrue);
      expect(samples.last.name, 'DP-2');
      await service.stop();
      expect(second.closed, isTrue);
      expect(disconnects, 1);
    },
  );

  test(
    'Sway rejects malformed event frames and releases the event connection',
    () async {
      final connection = TestSwayConnection();
      var disconnects = 0;
      final service = PomoSwayFollowService(
        connect: (_) async => connection,
        request: (_, _, type) async => type == 3
            ? [
                {
                  'name': 'DP-1',
                  'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
                },
              ]
            : [
                {'focused': true, 'output': 'DP-1'},
              ],
      );
      await service.start('/tmp/sway.sock', (_) {}, () => ++disconnects);
      connection.events.add(List.filled(14, 0));
      await settleEvents();
      expect(disconnects, 1);
      expect(connection.closed, isTrue);
      expect(service.running, isFalse);
      await service.stop();
    },
  );

  test(
    'unknown Wayland desktops remain fixed-monitor and stale sockets fail closed',
    () async {
      final transport = LinuxPomoFollowTransport(
        environment: {'SWAYSOCK': '/tmp/stale'},
        request: (_, _, _) async => throw const SocketException('Disconnected'),
      );
      expect(
        await transport.probe(
          const PomoEnvironment(backend: 'wayland', desktop: 'labwc'),
        ),
        PomoFollowSource.none,
      );
      transport.dispose();
    },
  );

  test(
    'KWin callback validates sender, live owner and finite monitor-only report',
    () async {
      String? owner = ':1.42';
      final samples = <PomoMonitorSample>[];
      final receiver = PomoKwinReceiver(
        path: DBusObjectPath('/test'),
        expectedOwner: ':1.42',
        resolveOwner: () async => owner,
        onSample: samples.add,
      );
      DBusMethodCall call(String sender, String report) => DBusMethodCall(
        sender: sender,
        interface: 'com.pomodoist.Pomo.Follow',
        name: 'Report',
        values: [DBusString(report)],
      );
      final report = jsonEncode({
        'name': 'DP-1',
        'x': 0,
        'y': -20,
        'width': 1920,
        'height': 1080,
      });
      expect(
        await receiver.handleMethodCall(call(':1.99', report)),
        isA<DBusMethodErrorResponse>(),
      );
      expect(samples, isEmpty);
      expect(
        await receiver.handleMethodCall(call(':1.42', report)),
        isA<DBusMethodSuccessResponse>(),
      );
      expect(samples.single.name, 'DP-1');
      expect(samples.single.cursorX, isNull);
      owner = ':1.43';
      expect(
        await receiver.handleMethodCall(call(':1.42', report)),
        isA<DBusMethodErrorResponse>(),
      );
      expect(samples.length, 1);
      owner = ':1.42';
      expect(
        await receiver.handleMethodCall(call(':1.42', '{"name":"bad"}')),
        isA<DBusMethodErrorResponse>(),
      );
      expect(samples.length, 1);
    },
  );

  test(
    'temporary KWin script reports screenAt cursor output without window data',
    () {
      final script = buildPomoKwinScript(
        ':1.88',
        '/com/pomodoist/Pomo/Follow/test',
      );
      expect(script, contains('workspace.screenAt(workspace.cursorPos)'));
      expect(script, contains('workspace.cursorPosChanged.connect(report)'));
      expect(script, contains('workspace.cursorPosChanged.disconnect(report)'));
      expect(script, isNot(contains('activeWindow')));
      expect(script, isNot(contains('print(')));
    },
  );

  test('Sway socket framing handles split binary replies', () async {
    final directory = await Directory.systemTemp.createTemp('pomo-ipc-test-');
    final path = '${directory.path}/ipc.sock';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final subscription = server.listen((socket) {
      socket.listen((request) async {
        expect(ascii.decode(request.take(6).toList()), 'i3-ipc');
        final body = utf8.encode('[{"name":"DP-1"}]');
        final header = ByteData(8)
          ..setUint32(0, body.length, Endian.little)
          ..setUint32(4, 3, Endian.little);
        socket.add([
          ...ascii.encode('i3-ipc'),
          ...header.buffer.asUint8List().take(2),
        ]);
        await socket.flush();
        socket.add([...header.buffer.asUint8List().skip(2), ...body]);
        await socket.flush();
        await socket.close();
      });
    });
    try {
      expect(await requestPomoSocket(path, '', 3), [
        {'name': 'DP-1'},
      ]);
    } finally {
      await subscription.cancel();
      await server.close();
      await directory.delete(recursive: true);
    }
  });
}
