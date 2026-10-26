import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dbus/dbus.dart';

import 'distraction_wayland_types.dart';
import 'pomo_follow_transport_io.dart' show requestPomoSocket;

DistractionWaylandAdapter? createDistractionWaylandAdapter(
  void Function(String, Object?) event,
  Future<void> Function(String, Map<String, Object?>) native,
) =>
    Platform.isLinux &&
        (Platform.environment['XDG_SESSION_TYPE'] == 'wayland' ||
            Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty == true)
    ? LinuxDistractionWaylandAdapter(event: event, native: native)
    : null;

/// Compositor commands use bounded local IPC. Window handles/workspaces remain
/// local; only public app identities reach the gateway's discovery streams.
class LinuxDistractionWaylandAdapter extends DistractionWaylandAdapter {
  LinuxDistractionWaylandAdapter({
    required this.event,
    required this.native,
    Map<String, String>? environment,
  }) : environment = environment ?? Platform.environment;
  final void Function(String, Object?) event;
  final Future<void> Function(String, Map<String, Object?>) native;
  final Map<String, String> environment;
  final DBusClient _bus = DBusClient.session();
  String? _kind, _socket;
  String? _last, _attempted;
  bool _discovery = false, _busy = false, _closed = false;
  Future<void> _operations = Future<void>.value();
  Future<void> _serialize(Future<void> Function() action) {
    final result = _operations.then((_) => action());
    _operations = result.catchError((Object _) {});
    return result;
  }

  Set<String> _blocked = {};
  Map<String, Object?> _snapshot = {};
  DateTime? _expires;
  DateTime _snapshotAt = DateTime.now();
  Timer? _timer;
  final Map<String, DistractionWaylandWindow> _changed = {};
  final _kwin = _KwinQuery();

  DBusRemoteObject get _gnome => DBusRemoteObject(
    _bus,
    name: 'com.pomodoist.Pomo.Gnome1',
    path: DBusObjectPath('/com/pomodoist/Pomo/Gnome1'),
  );

  Future<Map> _gnomeCall(Map<String, Object?> request) async {
    final result = await _gnome
        .callMethod('com.pomodoist.Pomo.Gnome1', 'Distractions', [
          DBusString(jsonEncode(request)),
        ], replySignature: DBusSignature('s'))
        .timeout(const Duration(seconds: 2));
    final raw = result.returnValues.single.asString();
    if (raw.length > 512 * 1024) {
      throw const FormatException('Bridge response too large');
    }
    final value = jsonDecode(raw);
    if (value is! Map) throw const FormatException('Invalid bridge response');
    return value;
  }

  @override
  Future<Map<String, Object?>?> capabilities() async {
    final desktop = (environment['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase();
    if (desktop.contains('gnome')) {
      try {
        final capabilities = await _gnomeCall({'action': 'capabilities'});
        if (capabilities['supported'] == true) {
          _kind = 'gnome';
          return Map<String, Object?>.from(capabilities);
        }
      } catch (_) {
        /* An older/disabled extension has no distraction protocol. */
      }
    }
    if (desktop.contains('kde') || desktop.contains('plasma')) {
      try {
        await _kwin.query(const {}, const {});
        _kind = 'kwin';
        return _capabilities('kwin-scripting');
      } catch (_) {
        /* Scripting is optional and can be disabled by the compositor. */
      }
    }
    final signature = environment['HYPRLAND_INSTANCE_SIGNATURE'];
    if (signature != null && RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(signature)) {
      for (final root in [
        if (environment['XDG_RUNTIME_DIR'] != null)
          '${environment['XDG_RUNTIME_DIR']}/hypr',
        '/tmp/hypr',
      ]) {
        final path = '$root/$signature/.socket.sock';
        try {
          if (await requestPomoSocket(path, 'j/activewindow', null) is Map) {
            _kind = 'hyprland';
            _socket = path;
            return _capabilities('hyprland-ipc');
          }
        } catch (_) {
          /* Probe the other supported runtime location. */
        }
      }
    }
    final sway = environment['SWAYSOCK'];
    if (sway != null && sway.startsWith('/')) {
      try {
        if (await requestPomoSocket(sway, '', 4) is Map) {
          _kind = 'sway';
          _socket = sway;
          return _capabilities('sway-ipc');
        }
      } catch (_) {
        /* A stale socket does not establish coverage. */
      }
    }
    return {
      'supported': false,
      'discoveryAvailable': false,
      'platform': 'linux',
      'reason':
          'No supported compositor adapter responded. GNOME requires the updated Pomodoist extension; Plasma requires KWin scripting. Sway and Hyprland require their local IPC sockets.',
    };
  }

  Map<String, Object?> _capabilities(String adapter) => {
    'supported': true,
    'discoveryAvailable': true,
    'platform': 'linux',
    'adapter': adapter,
  };

  void _events(Map response) {
    final events = response['events'];
    if (events is! List) return;
    for (final entry in events.take(64)) {
      if (entry is Map && entry['method'] is String) {
        if (entry['method'] == 'hideShield') {
          unawaited(native('hideShield', const {}));
          continue;
        }
        event(entry['method'] as String, entry['app']);
        if (entry['method'] == 'blockedAttempt') unawaited(_show());
      }
    }
  }

  @override
  Future<void> command(String method, Map<String, Object?> arguments) =>
      _serialize(() => _command(method, arguments));

  Future<void> _command(String method, Map<String, Object?> arguments) async {
    if (_kind == null) await capabilities();
    if (_kind == null) throw StateError('No supported Wayland compositor');
    if (method == 'startDiscovery') _discovery = true;
    if (method == 'stopDiscovery') _discovery = false;
    if (method == 'clearProtection' ||
        method == 'setProtection' && arguments['active'] == false) {
      _expires = null;
      _blocked.clear();
      await _restore();
      await native('clearProtection', const {});
    }
    if (method == 'setProtection' && arguments['active'] == true) {
      _snapshot = arguments;
      _snapshotAt = DateTime.now();
      _expires = DateTime.tryParse(arguments['expiresAt'] as String? ?? '');
      _blocked = (arguments['blockedApps'] as List)
          .whereType<String>()
          .where((id) => id.startsWith('linux:'))
          .toSet();
    }
    if (method == 'setProtection' && arguments['active'] == true) {
      await native('configureProtection', arguments);
    }
    if (_kind == 'gnome') {
      _events(
        await _gnomeCall({
          'action': method,
          'active': arguments['active'],
          'blockedApps': arguments['blockedApps'],
          'expiresAt': arguments['expiresAt'],
        }),
      );
    }
    _timer?.cancel();
    _timer = null;
    if (!_closed && (_discovery || _expires != null)) {
      _timer = Timer.periodic(const Duration(milliseconds: 750), (_) {
        if (!_busy) unawaited(_serialize(_tick));
      });
      await _tick();
    }
  }

  Future<void> _show() {
    final original = (_snapshot['remainingSeconds'] as int?) ?? 0;
    final elapsed = _snapshot['countdown'] == false
        ? 0
        : DateTime.now().difference(_snapshotAt).inSeconds;
    return native('setShield', {
      ..._snapshot,
      'remainingSeconds': max(0, original - elapsed),
    });
  }

  Future<void> _tick() async {
    if (_busy || _closed) return;
    _busy = true;
    try {
      if (_expires != null && !_expires!.isAfter(DateTime.now())) {
        _expires = null;
        _blocked.clear();
        await _restore();
        await native('clearProtection', const {});
        if (!_discovery) {
          _timer?.cancel();
          _timer = null;
        }
      }
      if (_kind == 'gnome') {
        _events(await _gnomeCall({'action': 'poll'}));
        return;
      }
      DistractionWaylandWindow? window;
      if (_kind == 'sway') {
        window = parseDistractionSwayWindow(
          await requestPomoSocket(_socket!, '', 4),
        );
      }
      if (_kind == 'hyprland') {
        window = parseDistractionHyprlandWindow(
          await requestPomoSocket(_socket!, 'j/activewindow', null),
        );
      }
      if (_kind == 'kwin') {
        final report = await _kwin.query(
          _expires == null ? {} : _blocked,
          const {},
          expiresAt: _expires,
        );
        window = DistractionWaylandWindow.fromMap(report);
        if (window != null && report['minimized'] == true) {
          _changed.putIfAbsent(window.key, () => window!);
        }
      }
      if (window == null) return;
      if (_discovery && _last != window.id) {
        _last = window.id;
        event('foregroundApp', window.publicIdentity);
      }
      if (_expires?.isAfter(DateTime.now()) == true &&
          _blocked.contains(window.id)) {
        if (_attempted != window.id) {
          _attempted = window.id;
          event('blockedAttempt', window.publicIdentity);
        }
        if (_kind == 'sway') {
          final result = await requestPomoSocket(
            _socket!,
            '[con_id=${window.key}] move scratchpad',
            0,
          );
          if (result is! List ||
              result.any(
                (entry) => entry is! Map || entry['success'] != true,
              )) {
            throw StateError('Sway rejected minimize');
          }
          _changed.putIfAbsent(window.key, () => window!);
        }
        if (_kind == 'hyprland' && window.workspace > 0) {
          final result = await _hyprCommand(
            _socket!,
            'dispatch movetoworkspacesilent special:pomodoist-$pid,address:${window.key}',
          );
          if (result != 'ok') throw StateError('Hyprland rejected minimize');
          _changed.putIfAbsent(window.key, () => window!);
        }
        await _show();
      } else {
        _attempted = null;
        await native('hideShield', const {});
      }
    } catch (_) {
      // An unavailable adapter must not keep an expired native shield alive.
      if (_expires != null && !_expires!.isAfter(DateTime.now())) {
        await native('clearProtection', const {});
      }
    } finally {
      _busy = false;
    }
  }

  Future<String> _hyprCommand(String path, String command) async {
    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
      timeout: const Duration(milliseconds: 500),
    );
    final result = Completer<String>();
    final bytes = <int>[];
    final subscription = socket.listen(
      (chunk) {
        bytes.addAll(chunk);
        if (bytes.length > 4096 && !result.isCompleted) {
          result.completeError(
            const FormatException('Compositor reply too large'),
          );
        }
      },
      onDone: () {
        if (!result.isCompleted) result.complete(utf8.decode(bytes).trim());
      },
      onError: (Object error) {
        if (!result.isCompleted) result.completeError(error);
      },
    );
    try {
      socket.write(command);
      await socket.flush();
      return await result.future.timeout(const Duration(seconds: 1));
    } finally {
      socket.destroy();
      await subscription.cancel();
    }
  }

  Future<void> _restore() async {
    if (_changed.isEmpty) return;
    if (_kind == 'kwin') {
      await _kwin.query(const {}, {
        for (final window in _changed.values) window.key: window.id,
      });
    } else if (_kind == 'sway') {
      final tree = await requestPomoSocket(_socket!, '', 4);
      final live = distractionSwayWindows(tree);
      for (final window in _changed.values) {
        if (live.any(
          (current) =>
              current.key == window.key &&
              current.id == window.id &&
              current.scratchpad,
        )) {
          await requestPomoSocket(
            _socket!,
            '[con_id=${window.key}] move container to workspace ${jsonEncode(window.workspaceName)}',
            0,
          );
        }
      }
    } else if (_kind == 'hyprland') {
      final clients = await requestPomoSocket(_socket!, 'j/clients', null);
      if (clients is! List) return;
      for (final window in _changed.values) {
        if (clients.any(
          (entry) =>
              entry is Map &&
              entry['address'] == window.key &&
              'linux:${entry['initialClass'] ?? entry['class']}' == window.id &&
              entry['workspace'] is Map &&
              entry['workspace']['name'] == 'special:pomodoist-$pid',
        )) {
          await _hyprCommand(
            _socket!,
            'dispatch movetoworkspacesilent ${window.workspace},address:${window.key}',
          );
        }
      }
    }
    _changed.clear();
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    _timer?.cancel();
    try {
      if (_kind != null) await command('clearProtection', const {});
      if (_kind == 'gnome') await _gnomeCall({'action': 'stopDiscovery'});
    } catch (_) {
      // The compositor may have exited before application disposal.
    } finally {
      await _kwin.dispose();
      await _bus.close();
    }
  }
}

class DistractionWaylandWindow {
  const DistractionWaylandWindow({
    required this.id,
    required this.name,
    required this.key,
    this.workspace = 0,
    this.workspaceName = '',
    this.scratchpad = false,
  });
  final String id, name, key, workspaceName;
  final int workspace;
  final bool scratchpad;
  Map<String, Object?> get publicIdentity => {
    'id': id,
    'name': name,
    'platform': 'linux',
  };
  static DistractionWaylandWindow? fromMap(Map value) {
    final id = value['id'], key = value['key'], name = value['name'];
    if (id is! String ||
        !RegExp(r'^linux:[^/\\\r\n]{1,480}$').hasMatch(id) ||
        name is! String ||
        key is! String) {
      return null;
    }
    if (id.toLowerCase().contains('pomodoist') ||
        const [
          'linux:plasmashell',
          'linux:gnome-shell',
          'linux:polkit-kde-authentication-agent-1',
        ].contains(id.toLowerCase())) {
      return null;
    }
    return DistractionWaylandWindow(id: id, name: name, key: key);
  }
}

DistractionWaylandWindow? parseDistractionHyprlandWindow(Object? raw) {
  if (raw is! Map || raw['pid'] == pid) return null;
  final id = raw['initialClass'] ?? raw['class'], key = raw['address'];
  if (id is! String ||
      key is! String ||
      !RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(key)) {
    return null;
  }
  final window = DistractionWaylandWindow.fromMap({
    'id': 'linux:$id',
    'name': id,
    'key': key,
  });
  if (window == null) return null;
  return DistractionWaylandWindow(
    id: window.id,
    name: window.name,
    key: key,
    workspace: raw['workspace'] is Map && raw['workspace']['id'] is int
        ? raw['workspace']['id'] as int
        : 0,
  );
}

List<DistractionWaylandWindow> distractionSwayWindows(Object? raw) {
  final result = <DistractionWaylandWindow>[];
  void visit(Object? node, String workspace) {
    if (node is! Map) return;
    if (node['type'] == 'workspace' && node['name'] is String) {
      workspace = node['name'] as String;
    }
    final identity =
        node['app_id'] ??
        (node['window_properties'] is Map
            ? node['window_properties']['class']
            : null);
    final key = node['id'];
    if (identity is String && key is int && key > 0 && node['pid'] != pid) {
      final window = DistractionWaylandWindow.fromMap({
        'id': 'linux:$identity',
        'name': identity,
        'key': '$key',
      });
      if (window != null) {
        result.add(
          DistractionWaylandWindow(
            id: window.id,
            name: window.name,
            key: window.key,
            workspaceName: workspace,
            scratchpad:
                node['scratchpad_state'] != null &&
                node['scratchpad_state'] != 'none',
          ),
        );
      }
    }
    for (final field in ['nodes', 'floating_nodes']) {
      final children = node[field];
      if (children is! List) continue;
      for (final child in children) {
        visit(child, workspace);
      }
    }
  }

  visit(raw, '');
  return result;
}

DistractionWaylandWindow? parseDistractionSwayWindow(Object? raw) {
  String? focused;
  void visit(Object? value) {
    if (value is! Map) return;
    if (value['focused'] == true && value['id'] is int) {
      focused = '${value['id']}';
    }
    for (final field in ['nodes', 'floating_nodes']) {
      final children = value[field];
      if (children is! List) continue;
      for (final child in children) {
        visit(child);
      }
    }
  }

  visit(raw);
  for (final window in distractionSwayWindows(raw)) {
    if (window.key == focused && !window.scratchpad) return window;
  }
  return null;
}

/// shortcut: KWin uses one-shot scripts at 750 ms; replace with a persistent
/// authenticated helper if profiling shows compositor overhead.
/// One-shot scripts are unloaded after an authenticated reply. There is no
/// installed script, persistent compositor configuration, or title collection.
class _KwinQuery {
  final DBusClient _bus = DBusClient.session();
  Future<Map> query(
    Set<String> blocked,
    Map<String, String> restore, {
    DateTime? expiresAt,
  }) async {
    final owner = await _bus
        .getNameOwner('org.kde.KWin')
        .timeout(const Duration(seconds: 1));
    if (owner == null) throw StateError('KWin unavailable');
    final token = '${pid}_${Random.secure().nextInt(0x7fffffff)}';
    final receiver = _KwinReceiver(
      path: DBusObjectPath('/com/pomodoist/Distractions/$token'),
      expectedOwner: owner,
      bus: _bus,
    );
    await _bus.registerObject(receiver);
    final directory = await Directory.systemTemp.createTemp(
      'pomodoist-distractions-',
    );
    final name = 'pomodoist_distractions_$token';
    final scripting = DBusRemoteObject(
      _bus,
      name: 'org.kde.KWin',
      path: DBusObjectPath('/Scripting'),
    );
    try {
      final file = File('${directory.path}/distractions.js');
      await file.writeAsString(
        buildDistractionKwinScript(
          _bus.uniqueName,
          receiver.path.value,
          blocked,
          restore,
          expiresAt: expiresAt,
        ),
        flush: true,
      );
      final loaded = await scripting
          .callMethod('org.kde.kwin.Scripting', 'loadScript', [
            DBusString(file.path),
            DBusString(name),
          ], replySignature: DBusSignature('i'))
          .timeout(const Duration(seconds: 1));
      final id = loaded.returnValues.single.asInt32();
      if (id < 0) throw StateError('KWin scripting unavailable');
      await DBusRemoteObject(
            _bus,
            name: 'org.kde.KWin',
            path: DBusObjectPath('/Scripting/Script$id'),
          )
          .callMethod(
            'org.kde.kwin.Script',
            'run',
            const [],
            replySignature: DBusSignature(''),
          )
          .timeout(const Duration(seconds: 1));
      return await receiver.result.future.timeout(const Duration(seconds: 1));
    } finally {
      try {
        await scripting
            .callMethod('org.kde.kwin.Scripting', 'unloadScript', [
              DBusString(name),
            ], replySignature: DBusSignature('b'))
            .timeout(const Duration(seconds: 1));
      } catch (_) {
        /* Compositor exited. */
      }
      await _bus.unregisterObject(receiver);
      await directory.delete(recursive: true);
    }
  }

  Future<void> dispose() => _bus.close();
}

class _KwinReceiver extends DBusObject {
  _KwinReceiver({
    required DBusObjectPath path,
    required this.expectedOwner,
    required this.bus,
  }) : super(path);
  final String expectedOwner;
  final DBusClient bus;
  final result = Completer<Map>();
  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'com.pomodoist.Distractions' ||
        call.name != 'Report' ||
        call.signature != DBusSignature('s')) {
      return DBusMethodErrorResponse.unknownMethod();
    }
    if (call.sender != expectedOwner ||
        await bus.getNameOwner('org.kde.KWin') != expectedOwner) {
      return DBusMethodErrorResponse('org.freedesktop.DBus.Error.AccessDenied');
    }
    try {
      final text = call.values.single.asString();
      if (text.length > 4096) throw const FormatException('Report too large');
      final value = jsonDecode(text);
      if (value is! Map) throw const FormatException('Invalid report');
      if (!result.isCompleted) result.complete(value);
      return DBusMethodSuccessResponse(const []);
    } catch (_) {
      return DBusMethodErrorResponse.invalidArgs();
    }
  }
}

String buildDistractionKwinScript(
  String destination,
  String path,
  Set<String> blocked,
  Map<String, String> restore, {
  DateTime? expiresAt,
}) =>
    '''
(function () {
 var blocked = ${jsonEncode(blocked.toList())}, restore = ${jsonEncode(restore)}, expires = ${expiresAt?.millisecondsSinceEpoch ?? 9007199254740991};
 function identity(w) { return "linux:" + String(w.desktopFileName || w.resourceClass || "").replace(/\\.desktop\$/, ""); }
 var windows = workspace.windowList();
 windows.forEach(function(w) { var key=String(w.internalId); if(restore[key] === identity(w) && w.minimized) w.minimized=false; });
 var w=workspace.activeWindow, report={};
 if (w && w.normalWindow && w.pid !== $pid && !w.specialWindow) {
   var id=identity(w); report={id:id,name:id.substring(6),key:String(w.internalId)};
   if(blocked.indexOf(id)!==-1 && Date.now()<expires && w.minimizable && !w.minimized) { w.minimized=true; report.minimized=true; }
 }
 callDBus(${jsonEncode(destination)},${jsonEncode(path)},"com.pomodoist.Distractions","Report",JSON.stringify(report));
})();
''';
