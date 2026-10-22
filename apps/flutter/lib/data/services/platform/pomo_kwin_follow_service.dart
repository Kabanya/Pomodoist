import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';

const _kwinName = 'org.kde.KWin';
const _scriptingInterface = 'org.kde.kwin.Scripting';
const _receiverInterface = 'com.pomodoist.Pomo.Follow';
const pomoKwinScriptInterface = 'org.kde.kwin.Script';

/// KWin Plasma 6 exports AbstractScript beneath `/Scripting/Script<id>`.
DBusObjectPath pomoKwinScriptPath(int scriptId) =>
    DBusObjectPath('/Scripting/Script$scriptId');

/// A temporary, per-process KWin script. No package installation or settings edit.
class PomoKwinFollowService {
  PomoKwinFollowService({DBusClient? client})
    : _client = client ?? DBusClient.session(),
      _ownsClient = client == null;
  final DBusClient _client;
  final bool _ownsClient;
  PomoKwinReceiver? _receiver;
  Directory? _directory;
  String? _scriptName, _owner;
  void Function()? _onDisconnect;
  DateTime? _lastConnectionCheck;

  DBusRemoteObject get _scripting => DBusRemoteObject(
    _client,
    name: _kwinName,
    path: DBusObjectPath('/Scripting'),
  );

  Future<bool> isAvailable() async {
    try {
      final owner = await _client
          .getNameOwner(_kwinName)
          .timeout(const Duration(seconds: 1));
      if (_owner != null && owner != _owner) _onDisconnect?.call();
      if (owner == null) return false;
      // A running compositor alone does not establish that scripting is exposed.
      // Introspection is read-only and does not install or execute a helper.
      final node = await _scripting.introspect().timeout(
        const Duration(seconds: 1),
      );
      return node.interfaces.any(
        (interface) =>
            interface.name == _scriptingInterface &&
            interface.methods.any((method) => method.name == 'loadScript') &&
            interface.methods.any((method) => method.name == 'unloadScript'),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> start(
    void Function(PomoMonitorSample) onSample,
    void Function() onDisconnect,
  ) async {
    await stop();
    try {
      await _client.ping().timeout(const Duration(seconds: 1));
      _owner = await _client.getNameOwner(_kwinName);
      if (_owner == null) throw StateError('KWin is unavailable');
      _onDisconnect = onDisconnect;
      final id = '${pid}_${Random.secure().nextInt(0x7fffffff)}';
      final path = '/com/pomodoist/Pomo/Follow/$id';
      final ready = Completer<void>();
      _receiver = PomoKwinReceiver(
        path: DBusObjectPath(path),
        expectedOwner: _owner!,
        resolveOwner: () => _client.getNameOwner(_kwinName),
        onSample: (sample) {
          if (!ready.isCompleted) ready.complete();
          onSample(sample);
        },
      );
      await _client.registerObject(_receiver!);
      _directory = await Directory.systemTemp.createTemp('pomodoist-pomo-');
      final script = File('${_directory!.path}/follow.js');
      await script.writeAsString(
        buildPomoKwinScript(_client.uniqueName, path),
        flush: true,
      );
      _scriptName = 'pomodoist_pomo_$id';
      final loaded = await _scripting
          .callMethod(_scriptingInterface, 'loadScript', [
            DBusString(script.path),
            DBusString(_scriptName!),
          ], replySignature: DBusSignature('i'))
          .timeout(const Duration(seconds: 2));
      final scriptId = loaded.returnValues.single.asInt32();
      if (scriptId < 0) throw StateError('KWin rejected the temporary script');
      await DBusRemoteObject(
            _client,
            name: _kwinName,
            path: pomoKwinScriptPath(scriptId),
          )
          .callMethod(
            pomoKwinScriptInterface,
            'run',
            const [],
            replySignature: DBusSignature(''),
          )
          .timeout(const Duration(seconds: 2));
      await ready.future.timeout(const Duration(seconds: 2));
      _lastConnectionCheck = DateTime.now();
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> checkConnection() async {
    final previous = _lastConnectionCheck;
    if (previous != null &&
        DateTime.now().difference(previous) < const Duration(seconds: 2)) {
      return;
    }
    _lastConnectionCheck = DateTime.now();
    if (!await isAvailable()) throw StateError('KWin disconnected');
  }

  Future<void> stop() async {
    _onDisconnect = null;
    _owner = null;
    _lastConnectionCheck = null;
    final scriptName = _scriptName;
    _scriptName = null;
    if (scriptName != null) {
      try {
        await _scripting
            .callMethod(_scriptingInterface, 'unloadScript', [
              DBusString(scriptName),
            ], replySignature: DBusSignature('b'))
            .timeout(const Duration(seconds: 1));
      } catch (_) {
        /* The compositor may already have exited. */
      }
    }
    final receiver = _receiver;
    _receiver = null;
    if (receiver != null) {
      try {
        await _client.unregisterObject(receiver);
      } catch (_) {
        /* Bus closed. */
      }
    }
    final directory = _directory;
    _directory = null;
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        /* Best effort on exit. */
      }
    }
  }

  void dispose() {
    unawaited(
      stop()
          .then((_) async {
            if (_ownsClient) await _client.close();
          })
          .catchError((Object _) {}),
    );
  }
}

/// Authenticates every callback against both the start owner and current bus owner.
class PomoKwinReceiver extends DBusObject {
  PomoKwinReceiver({
    required DBusObjectPath path,
    required this.expectedOwner,
    required this.resolveOwner,
    required this.onSample,
  }) : super(path);
  final String expectedOwner;
  final Future<String?> Function() resolveOwner;
  final void Function(PomoMonitorSample) onSample;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _receiverInterface ||
        methodCall.name != 'Report') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    if (methodCall.signature != DBusSignature('s')) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    String? currentOwner;
    try {
      currentOwner = await resolveOwner().timeout(const Duration(seconds: 1));
    } catch (_) {
      /* A closed bus cannot authenticate a sender. */
    }
    if (methodCall.sender != expectedOwner || currentOwner != expectedOwner) {
      return DBusMethodErrorResponse('org.freedesktop.DBus.Error.AccessDenied');
    }
    try {
      final text = methodCall.values.single.asString();
      if (text.length > 4096) throw const FormatException('Report too large');
      final raw = jsonDecode(text);
      if (raw is! Map || raw['name'] is! String) {
        throw const FormatException('Invalid output');
      }
      double number(String key) {
        final value = raw[key];
        if (value is! num || !value.isFinite) {
          throw const FormatException('Invalid geometry');
        }
        return value.toDouble();
      }

      final width = number('width'), height = number('height');
      if (width <= 0 || height <= 0) {
        throw const FormatException('Empty output');
      }
      onSample(
        PomoMonitorSample(
          name: raw['name'] as String,
          x: number('x'),
          y: number('y'),
          width: width,
          height: height,
        ),
      );
      return DBusMethodSuccessResponse(const []);
    } catch (_) {
      return DBusMethodErrorResponse.invalidArgs();
    }
  }
}

/// The helper emits monitor geometry only; cursor coordinates stay in KWin.
String buildPomoKwinScript(String destination, String objectPath) =>
    '''
(function () {
    var last = "";
    var connected = true;
    function report() {
        if (!connected) return;
        var output = workspace.screenAt(workspace.cursorPos);
        if (!output) return;
        var geometry = output.geometry;
        var message = JSON.stringify({name: output.name,
            x: geometry.x, y: geometry.y,
            width: geometry.width, height: geometry.height});
        if (message === last) return;
        last = message;
        callDBus(${jsonEncode(destination)}, ${jsonEncode(objectPath)},
            "$_receiverInterface", "Report", message);
        callDBus("org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "NameHasOwner", ${jsonEncode(destination)},
            function (alive) {
                if (!alive && connected) {
                    connected = false;
                    workspace.cursorPosChanged.disconnect(report);
                    workspace.screensChanged.disconnect(report);
                }
            });
    }
    workspace.cursorPosChanged.connect(report);
    workspace.screensChanged.connect(report);
    report();
})();
''';
