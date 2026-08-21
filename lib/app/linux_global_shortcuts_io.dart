import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import 'hyprland_global_shortcut.dart';
import 'linux_host_app_id.dart';

const _destination = 'org.freedesktop.portal.Desktop';
const _desktopPath = '/org/freedesktop/portal/desktop';
const _globalShortcuts = 'org.freedesktop.portal.GlobalShortcuts';
const _hostRegistry = 'org.freedesktop.host.portal.Registry';
const _requestInterface = 'org.freedesktop.portal.Request';

typedef LinuxAppIdResolver = Future<String> Function();

class LinuxGlobalShortcutsPortal {
  LinuxGlobalShortcutsPortal({
    DBusClient? client,
    bool? sandboxed,
    bool manageHyprlandShortcut = true,
    Duration requestTimeout = const Duration(minutes: 2),
    LinuxAppIdResolver? appIdResolver,
    HyprlandGlobalShortcut? hyprlandShortcut,
  }) : _client = client ?? DBusClient.session(),
       _ownsClient = client == null,
       _sandboxed = sandboxed ?? File('/.flatpak-info').existsSync(),
       _requestTimeout = requestTimeout,
       _appIdResolver = appIdResolver ?? LinuxHostAppIdResolver().resolve,
       _hyprlandShortcut = manageHyprlandShortcut && _isHyprlandSession()
           ? hyprlandShortcut ?? HyprlandGlobalShortcut()
           : null {
    _desktop = DBusRemoteObject(
      _client,
      name: _destination,
      path: DBusObjectPath(_desktopPath),
    );
  }

  final DBusClient _client;
  final bool _ownsClient;
  final bool _sandboxed;
  final Duration _requestTimeout;
  final LinuxAppIdResolver _appIdResolver;
  final HyprlandGlobalShortcut? _hyprlandShortcut;
  late final DBusRemoteObject _desktop;
  Future<String>? _registeredAppId;
  DBusObjectPath? _sessionPath;
  StreamSubscription<DBusSignal>? _activationSubscription;

  Future<bool> isAvailable() async {
    try {
      await _ensureHostIdentity();
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
    final appId = await _ensureHostIdentity();
    try {
      final token = 'pomodoist_${DateTime.now().microsecondsSinceEpoch}';
      final createRequestToken = '${token}_request';
      final createResult = await _callRequest('CreateSession', [
        DBusDict.stringVariant({
          'handle_token': DBusString(createRequestToken),
          'session_handle_token': DBusString('${token}_session'),
        }),
      ], handleToken: createRequestToken);
      final sessionPath = _sessionHandle(createResult['session_handle']);
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

      final bindRequestToken = '${token}_bind';
      await _callRequest('BindShortcuts', [
        sessionPath,
        DBusArray(DBusSignature('(sa{sv})'), [
          DBusStruct([
            const DBusString('quick-add'),
            DBusDict.stringVariant({
              'description': const DBusString('Add a task in Pomodoist'),
              'preferred_trigger': DBusString(preferredTrigger),
            }),
          ]),
        ]),
        const DBusString(''),
        DBusDict.stringVariant({'handle_token': DBusString(bindRequestToken)}),
      ], handleToken: bindRequestToken);
      await _hyprlandShortcut?.replace(
        portalTrigger: preferredTrigger,
        appId: appId,
      );
    } catch (_) {
      try {
        await disable();
      } on Object {
        // Preserve the registration error that caused cleanup.
      }
      rethrow;
    }
  }

  Future<void> disable() async {
    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    try {
      await _hyprlandShortcut?.remove();
    } catch (error, stackTrace) {
      cleanupError = error;
      cleanupStackTrace = stackTrace;
    }

    await _activationSubscription?.cancel();
    _activationSubscription = null;
    final sessionPath = _sessionPath;
    _sessionPath = null;
    if (sessionPath != null) {
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
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
    }
  }

  Future<void> dispose() async {
    try {
      await disable();
    } on Object {
      // Disposal is best-effort; explicit disable still reports failures.
    }
    if (_ownsClient) await _client.close();
  }

  Future<String> _ensureHostIdentity() {
    return _registeredAppId ??= _registerHostIdentity();
  }

  Future<String> _registerHostIdentity() async {
    final appId = await _appIdResolver();
    if (_sandboxed) return appId;
    try {
      await _desktop.callMethod(_hostRegistry, 'Register', [
        DBusString(appId),
        DBusDict.stringVariant(const {}),
      ], replySignature: DBusSignature(''));
    } on DBusMethodResponseException catch (error) {
      if (error.errorName != 'org.freedesktop.DBus.Error.UnknownInterface' &&
          error.errorName != 'org.freedesktop.DBus.Error.UnknownMethod') {
        rethrow;
      }
      // Older portal releases inferred host identity without this interface.
    }
    return appId;
  }

  Future<Map<String, DBusValue>> _callRequest(
    String method,
    List<DBusValue> values, {
    required String handleToken,
  }) async {
    await _client.ping();
    final sender = _client.uniqueName.substring(1).replaceAll('.', '_');
    final requestPath = DBusObjectPath(
      '$_desktopPath/request/$sender/$handleToken',
    );
    final signalCompleter = Completer<DBusSignal>();
    final subscription = DBusSignalStream(
      _client,
      path: requestPath,
      interface: _requestInterface,
      name: 'Response',
      signature: DBusSignature('ua{sv}'),
    ).listen(signalCompleter.complete, onError: signalCompleter.completeError);

    try {
      // AddMatch is queued by listen(); this round trip confirms it reached
      // the bus before the portal can emit an immediate Response signal.
      await _client.ping();
      final response = await _desktop.callMethod(
        _globalShortcuts,
        method,
        values,
        replySignature: DBusSignature('o'),
        allowInteractiveAuthorization: true,
      );
      final returnedPath = response.returnValues.single.asObjectPath();
      if (returnedPath != requestPath) {
        throw StateError(
          'GlobalShortcuts portal returned an unexpected request path.',
        );
      }
      final signal = await signalCompleter.future.timeout(_requestTimeout);
      final result = signal.values[1].asStringVariantDict();
      if (signal.values[0].asUint32() != 0) {
        throw StateError('GlobalShortcuts portal rejected $method.');
      }
      return result;
    } finally {
      await subscription.cancel();
    }
  }
}

DBusObjectPath? _sessionHandle(DBusValue? value) {
  if (value is DBusObjectPath) return value;
  if (value is! DBusString) return null;
  return DBusObjectPath(value.asString());
}

bool _isHyprlandSession() {
  if (Platform.environment['HYPRLAND_INSTANCE_SIGNATURE']?.isNotEmpty == true) {
    return true;
  }
  final desktops = [
    Platform.environment['XDG_CURRENT_DESKTOP'],
    Platform.environment['XDG_SESSION_DESKTOP'],
  ];
  return desktops.whereType<String>().any(
    (desktop) => desktop
        .split(':')
        .any((name) => name.trim().toLowerCase() == 'hyprland'),
  );
}
