import 'dart:async';

import 'package:dbus/dbus.dart';

const _destination = 'org.freedesktop.portal.Desktop';
const _globalShortcuts = 'org.freedesktop.portal.GlobalShortcuts';

class LinuxGlobalShortcutsPortal {
  LinuxGlobalShortcutsPortal() : _client = DBusClient.session() {
    _desktop = DBusRemoteObject(
      _client,
      name: _destination,
      path: DBusObjectPath('/org/freedesktop/portal/desktop'),
    );
  }

  final DBusClient _client;
  late final DBusRemoteObject _desktop;
  DBusObjectPath? _sessionPath;
  StreamSubscription<DBusSignal>? _activationSubscription;

  Future<bool> isAvailable() async {
    try {
      final version = await _desktop.getProperty(
        _globalShortcuts,
        'version',
        signature: DBusSignature('u'),
      );
      return version.asUint32() >= 1;
    } catch (_) {
      return false;
    }
  }

  Future<void> enable({
    required String preferredTrigger,
    required FutureOr<void> Function() onActivated,
  }) async {
    await disable();
    final token = 'pomodoist_${DateTime.now().microsecondsSinceEpoch}';
    final createResult = await _callRequest('CreateSession', [
      DBusDict.stringVariant({
        'handle_token': DBusString('${token}_request'),
        'session_handle_token': DBusString('${token}_session'),
      }),
    ]);
    final sessionPath = createResult['session_handle']?.asObjectPath();
    if (sessionPath == null) {
      throw StateError('GlobalShortcuts portal did not create a session.');
    }
    _sessionPath = sessionPath;
    final signals = DBusRemoteObjectSignalStream(
      object: _desktop,
      interface: _globalShortcuts,
      name: 'Activated',
      signature: DBusSignature('osta{sv}'),
    );
    _activationSubscription = signals.listen((signal) {
      if (signal.values[0].asObjectPath() == sessionPath &&
          signal.values[1].asString() == 'quick-add') {
        unawaited(Future.sync(onActivated));
      }
    });

    try {
      await _callRequest('BindShortcuts', [
        sessionPath,
        DBusArray(DBusSignature('(sa{sv})'), [
          DBusStruct([
            DBusString('quick-add'),
            DBusDict.stringVariant({
              'description': DBusString('Add a task in Pomodoist'),
              'preferred_trigger': DBusString(preferredTrigger),
            }),
          ]),
        ]),
        const DBusString(''),
        DBusDict.stringVariant({'handle_token': DBusString('${token}_bind')}),
      ]);
    } catch (_) {
      await disable();
      rethrow;
    }
  }

  Future<void> disable() async {
    await _activationSubscription?.cancel();
    _activationSubscription = null;
    final sessionPath = _sessionPath;
    _sessionPath = null;
    if (sessionPath == null) return;
    try {
      await DBusRemoteObject(
        _client,
        name: _destination,
        path: sessionPath,
      ).callMethod(
        'org.freedesktop.portal.Session',
        'Close',
        const [],
        replySignature: DBusSignature(''),
      );
    } catch (_) {
      // The desktop may already have closed the session.
    }
  }

  Future<void> dispose() async {
    await disable();
    await _client.close();
  }

  Future<Map<String, DBusValue>> _callRequest(
    String method,
    List<DBusValue> values,
  ) async {
    final response = await _desktop.callMethod(
      _globalShortcuts,
      method,
      values,
      replySignature: DBusSignature('o'),
      allowInteractiveAuthorization: true,
    );
    final request = DBusRemoteObject(
      _client,
      name: _destination,
      path: response.returnValues.single.asObjectPath(),
    );
    final signal = await DBusRemoteObjectSignalStream(
      object: request,
      interface: 'org.freedesktop.portal.Request',
      name: 'Response',
      signature: DBusSignature('ua{sv}'),
    ).first.timeout(const Duration(minutes: 2));
    final result = signal.values[1].asStringVariantDict();
    if (signal.values[0].asUint32() != 0) {
      throw StateError('GlobalShortcuts portal rejected $method.');
    }
    return result;
  }
}
