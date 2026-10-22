import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';

abstract interface class PomoSwayConnection {
  Stream<List<int>> get messages;
  Future<void> send(List<int> bytes);
  Future<void> close();
}

typedef PomoSwayConnect = Future<PomoSwayConnection> Function(String path);

class _SocketConnection implements PomoSwayConnection {
  _SocketConnection(this.socket);
  final Socket socket;
  @override
  Stream<List<int>> get messages => socket;
  @override
  Future<void> send(List<int> bytes) async {
    socket.add(bytes);
    await socket.flush();
  }

  @override
  Future<void> close() async => socket.destroy();
}

Future<PomoSwayConnection> _openSwaySocket(String path) async =>
    _SocketConnection(
      await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      ),
    );

List<int> encodePomoSwayMessage(int type, String payload) {
  final body = utf8.encode(payload);
  final header = ByteData(8)
    ..setUint32(0, body.length, Endian.little)
    ..setUint32(4, type, Endian.little);
  return [...ascii.encode('i3-ipc'), ...header.buffer.asUint8List(), ...body];
}

/// Subscribes before taking snapshots, so workspace/output changes cannot fall
/// between the initial snapshot and event registration. No workspace polling.
class PomoSwayFollowService {
  PomoSwayFollowService({
    required PomoSocketRequest request,
    PomoSwayConnect? connect,
  }) : _request = request,
       _connect = connect ?? _openSwaySocket;
  final PomoSocketRequest _request;
  final PomoSwayConnect _connect;
  PomoSwayConnection? _connection;
  StreamSubscription<List<int>>? _subscription;
  Completer<bool>? _ack;
  List<int> _buffer = [];
  List<Map> _outputs = const [], _workspaces = const [];
  String? _path;
  void Function(PomoMonitorSample)? _onSample;
  void Function()? _onDisconnect;
  bool _running = false, _ready = false, _dirty = false;
  int? _refreshGeneration;
  int _generation = 0;
  bool get running => _running && _ready;

  Future<void> start(
    String path,
    void Function(PomoMonitorSample) onSample,
    void Function() onDisconnect,
  ) async {
    await stop();
    final generation = ++_generation;
    _running = true;
    _path = path;
    _onSample = onSample;
    _onDisconnect = onDisconnect;
    try {
      final connection = await _connect(
        path,
      ).timeout(const Duration(milliseconds: 750));
      if (!_valid(generation)) {
        await connection.close();
        return;
      }
      _connection = connection;
      final ack = _ack = Completer<bool>();
      final acknowledged = ack.future.timeout(
        const Duration(milliseconds: 750),
        onTimeout: () => false,
      );
      _subscription = connection.messages.listen(
        (bytes) => _read(bytes, generation),
        onError: (Object _) => _disconnected(generation),
        onDone: () => _disconnected(generation),
      );
      await connection.send(encodePomoSwayMessage(2, '["workspace","output"]'));
      if (!await acknowledged || !_valid(generation)) {
        throw StateError('Sway rejected the event subscription');
      }
      _ready = true;
      await _refresh(generation);
      if (!_valid(generation)) {
        throw StateError('Sway disconnected during snapshot');
      }
    } catch (_) {
      if (_valid(generation)) _disconnected(generation);
      rethrow;
    }
  }

  bool _valid(int generation) => _running && generation == _generation;

  void _read(List<int> bytes, int generation) {
    if (!_valid(generation)) return;
    _buffer.addAll(bytes);
    try {
      if (_buffer.length > 2 * 1024 * 1024) {
        throw const FormatException('Sway event too large');
      }
      while (_buffer.length >= 14) {
        if (ascii.decode(_buffer.take(6).toList(), allowInvalid: true) !=
            'i3-ipc') {
          throw const FormatException('Invalid Sway event header');
        }
        final header = ByteData.sublistView(Uint8List.fromList(_buffer), 6, 14);
        final length = header.getUint32(0, Endian.little);
        final type = header.getUint32(4, Endian.little);
        if (length > 1024 * 1024) {
          throw const FormatException('Sway event too large');
        }
        if (_buffer.length < length + 14) return;
        final body = jsonDecode(utf8.decode(_buffer.sublist(14, length + 14)));
        _buffer = _buffer.sublist(length + 14);
        if (type == 2) {
          final ack = _ack;
          if (ack != null && !ack.isCompleted) {
            ack.complete(body is Map && body['success'] == true);
          }
        } else if (type == 0x80000000 || type == 0x80000001) {
          if (body is! Map) throw const FormatException('Invalid Sway event');
          _dirty = true;
          if (_ready) unawaited(_refresh(generation));
        }
      }
    } catch (_) {
      _disconnected(generation);
    }
  }

  Future<void> _refresh(int generation) async {
    if (!_valid(generation)) return;
    if (_refreshGeneration == generation) {
      _dirty = true;
      return;
    }
    _refreshGeneration = generation;
    try {
      do {
        _dirty = false;
        final snapshots = await Future.wait([
          _request(_path!, '', 3),
          _request(_path!, '', 1),
        ]);
        if (!_valid(generation)) return;
        if (snapshots[0] is! List || snapshots[1] is! List) {
          throw const FormatException('Invalid Sway snapshot');
        }
        _outputs = (snapshots[0] as List).whereType<Map>().toList();
        _workspaces = (snapshots[1] as List).whereType<Map>().toList();
        _publish();
      } while (_dirty && _valid(generation));
    } catch (_) {
      _disconnected(generation);
    } finally {
      if (_refreshGeneration == generation) _refreshGeneration = null;
    }
  }

  void _publish() {
    final focused = _workspaces.where(
      (workspace) => workspace['focused'] == true,
    );
    final visible = _workspaces.where(
      (workspace) => workspace['visible'] == true,
    );
    final workspace = focused.isNotEmpty
        ? focused.first
        : visible.length == 1
        ? visible.single
        : null;
    if (workspace == null) return;
    final outputs = _outputs.where(
      (output) => output['name'] == workspace['output'],
    );
    if (outputs.isEmpty) return;
    final sample = parseSwayPomoOutput(outputs.first);
    if (sample != null) _onSample?.call(sample);
  }

  void _disconnected(int generation) {
    if (!_valid(generation)) return;
    final notify = _onDisconnect;
    unawaited(stop());
    notify?.call();
  }

  Future<void> stop() async {
    _running = _ready = _dirty = false;
    ++_generation;
    _onSample = null;
    _onDisconnect = null;
    _path = null;
    final ack = _ack;
    _ack = null;
    if (ack != null && !ack.isCompleted) ack.complete(false);
    final subscription = _subscription;
    _subscription = null;
    final connection = _connection;
    _connection = null;
    _buffer = [];
    _outputs = _workspaces = const [];
    try {
      if (subscription != null) await subscription.cancel();
    } catch (_) {
      /* The event stream may already be closed. */
    }
    try {
      if (connection != null) await connection.close();
    } catch (_) {
      /* A disconnected socket has no remaining tracking resources. */
    }
  }
}

double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

PomoMonitorSample? parseSwayPomoOutput(Map raw) {
  final rect = raw['rect'];
  if (rect is! Map || raw['active'] == false) return null;
  final x = _number(rect['x']), y = _number(rect['y']);
  final width = _number(rect['width']), height = _number(rect['height']);
  if (x == null ||
      y == null ||
      width == null ||
      height == null ||
      width <= 0 ||
      height <= 0) {
    return null;
  }
  return PomoMonitorSample(
    name: raw['name'] is String ? raw['name'] as String : null,
    x: x,
    y: y,
    width: width,
    height: height,
  );
}
