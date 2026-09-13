import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/linux_global_shortcuts_io.dart';

void main() {
  test('registers the host app before creating a shortcut session', () async {
    final harness = await _PortalHarness.start();
    addTearDown(harness.close);
    final portal = LinuxGlobalShortcutsPortal(
      client: harness.appClient,
      sandboxed: false,
      manageHyprlandShortcut: false,
      requestTimeout: const Duration(seconds: 1),
      appIdResolver: () async => 'com.finchforge.pomodoist',
    );
    addTearDown(portal.dispose);

    await portal.enable(preferredTrigger: 'CTRL+ALT+space', onActivated: () {});

    expect(harness.portal.calls, [
      'Registry.Register',
      'GlobalShortcuts.CreateSession',
      'GlobalShortcuts.BindShortcuts',
    ]);
    expect(harness.portal.registeredAppId, 'com.finchforge.pomodoist');
  });

  test('receives a portal response emitted before the method reply', () async {
    final harness = await _PortalHarness.start();
    addTearDown(harness.close);
    final portal = LinuxGlobalShortcutsPortal(
      client: harness.appClient,
      sandboxed: false,
      manageHyprlandShortcut: false,
      requestTimeout: const Duration(seconds: 1),
      appIdResolver: () async => 'com.finchforge.pomodoist',
    );
    addTearDown(portal.dispose);

    await portal
        .enable(preferredTrigger: 'CTRL+ALT+space', onActivated: () {})
        .timeout(const Duration(seconds: 2));

    expect(harness.portal.createResponseWasEmittedBeforeReply, isTrue);
    expect(harness.portal.bindResponseWasEmittedBeforeReply, isTrue);
  });
}

class _PortalHarness {
  _PortalHarness({
    required this.server,
    required this.appClient,
    required this.serviceClient,
    required this.portal,
  });

  final DBusServer server;
  final DBusClient appClient;
  final DBusClient serviceClient;
  final _PortalObject portal;

  static Future<_PortalHarness> start() async {
    final server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress.unix(dir: Directory.systemTemp),
    );
    final appClient = DBusClient(
      address,
      authClient: DBusAuthClient(uid: '1000'),
    );
    final serviceClient = DBusClient(
      address,
      authClient: DBusAuthClient(uid: '1000'),
    );
    final portal = _PortalObject();
    await serviceClient.requestName('org.freedesktop.portal.Desktop');
    await serviceClient.registerObject(portal);
    return _PortalHarness(
      server: server,
      appClient: appClient,
      serviceClient: serviceClient,
      portal: portal,
    );
  }

  Future<void> close() async {
    await appClient.close();
    await serviceClient.close();
    await server.close();
  }
}

class _PortalObject extends DBusObject {
  _PortalObject() : super(DBusObjectPath('/org/freedesktop/portal/desktop'));

  final calls = <String>[];
  String? registeredAppId;
  bool createResponseWasEmittedBeforeReply = false;
  bool bindResponseWasEmittedBeforeReply = false;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    final method = switch ((call.interface, call.name)) {
      ('org.freedesktop.host.portal.Registry', 'Register') =>
        'Registry.Register',
      ('org.freedesktop.portal.GlobalShortcuts', 'CreateSession') =>
        'GlobalShortcuts.CreateSession',
      ('org.freedesktop.portal.GlobalShortcuts', 'BindShortcuts') =>
        'GlobalShortcuts.BindShortcuts',
      _ => null,
    };
    if (method == null) return DBusMethodErrorResponse.unknownMethod();
    calls.add(method);

    if (method == 'Registry.Register') {
      registeredAppId = call.values.first.asString();
      return DBusMethodSuccessResponse();
    }

    final options = call.values.last.asStringVariantDict();
    final token = options['handle_token']!.asString();
    final sender = call.sender!.substring(1).replaceAll('.', '_');
    final requestPath = DBusObjectPath(
      '/org/freedesktop/portal/desktop/request/$sender/$token',
    );
    final request = DBusObject(requestPath);
    await client!.registerObject(request);

    final results = <String, DBusValue>{};
    if (method == 'GlobalShortcuts.CreateSession') {
      final sessionToken = options['session_handle_token']!.asString();
      results['session_handle'] = DBusString(
        '/org/freedesktop/portal/desktop/session/$sender/$sessionToken',
      );
    }
    await request.emitSignal('org.freedesktop.portal.Request', 'Response', [
      const DBusUint32(0),
      DBusDict.stringVariant(results),
    ]);
    if (method == 'GlobalShortcuts.CreateSession') {
      createResponseWasEmittedBeforeReply = true;
    } else {
      bindResponseWasEmittedBeforeReply = true;
    }
    return DBusMethodSuccessResponse([requestPath]);
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.freedesktop.portal.GlobalShortcuts' &&
        name == 'version') {
      return DBusGetPropertyResponse(const DBusUint32(1));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }
}
