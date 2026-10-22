import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';
import 'package:pomodoist/data/services/platform/pomo_follow_transport_stub.dart';
import 'package:pomodoist/data/services/platform/pomo_kwin_follow_service.dart';
import 'package:pomodoist/data/services/platform/pomo_sway_follow_service.dart';
import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

export 'package:pomodoist/data/services/platform/pomo_sway_follow_service.dart'
    show parseSwayPomoOutput;

PomoFollowTransport createTransport() => Platform.isLinux
    ? LinuxPomoFollowTransport()
    : UnsupportedPomoFollowTransport();

/// Compositor IPC is bounded, read-only, and never invokes a shell or CLI tool.
class LinuxPomoFollowTransport implements PomoFollowTransport {
  LinuxPomoFollowTransport({
    Map<String, String>? environment,
    PomoSocketRequest? request,
    PomoKwinFollowService? kwin,
    PomoSwayConnect? swayConnect,
  }) : _environment = environment ?? Platform.environment,
       _request = request ?? requestPomoSocket,
       _kwin = kwin ?? PomoKwinFollowService() {
    _sway = PomoSwayFollowService(request: _request, connect: swayConnect);
  }

  final Map<String, String> _environment;
  final PomoSocketRequest _request;
  final PomoKwinFollowService _kwin;
  late final PomoSwayFollowService _sway;
  String? _kind, _path;
  List<Map> _outputs = const [];
  bool _running = false;

  @override
  Future<PomoFollowSource> probe(PomoEnvironment environment) async {
    final desktop = environment.desktop.toLowerCase();
    if (environment.backend.toLowerCase() != 'wayland') {
      return PomoFollowSource.none;
    }
    if (desktop.contains('kde') || desktop.contains('plasma')) {
      return await _kwin.isAvailable()
          ? PomoFollowSource.cursor
          : PomoFollowSource.none;
    }
    final hyprland = _environment['HYPRLAND_INSTANCE_SIGNATURE'];
    if (hyprland != null && RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(hyprland)) {
      final runtime = _environment['XDG_RUNTIME_DIR'];
      final paths = [
        if (runtime != null) '$runtime/hypr/$hyprland/.socket.sock',
        '/tmp/hypr/$hyprland/.socket.sock',
      ];
      for (final path in paths) {
        try {
          final outputs = _mapList(await _request(path, 'j/monitors', null));
          if (outputs.isEmpty) continue;
          _path = path;
          _outputs = outputs;
          return PomoFollowSource.cursor;
        } catch (_) {
          /* A restarted compositor may use the other socket path. */
        }
      }
    }
    if (_sway.running) return PomoFollowSource.workspace;
    final sway = _environment['SWAYSOCK'];
    if (sway != null && sway.startsWith('/')) {
      try {
        final outputs = _mapList(await _request(sway, '', 3));
        if (outputs.isNotEmpty) {
          _path = sway;
          _outputs = outputs;
          return PomoFollowSource.workspace;
        }
      } catch (_) {
        /* No live Sway IPC socket. */
      }
    }
    return PomoFollowSource.none;
  }

  @override
  Future<void> start(
    PomoEnvironment environment,
    void Function(PomoMonitorSample) onSample,
    void Function() onDisconnect,
  ) async {
    await stop();
    final desktop = environment.desktop.toLowerCase();
    if (desktop.contains('kde') || desktop.contains('plasma')) {
      _kind = 'kwin';
      await _kwin.start(onSample, onDisconnect);
    } else {
      _kind = environment.followSource == PomoFollowSource.workspace
          ? 'sway'
          : 'hyprland';
      if (_path == null) throw StateError('No compositor IPC socket');
      if (_kind == 'sway') await _sway.start(_path!, onSample, onDisconnect);
    }
    _running = true;
  }

  @override
  Future<PomoMonitorSample?> sample() async {
    if (!_running) return null;
    if (_kind == 'kwin') {
      await _kwin.checkConnection();
      return null; // KWin pushes output changes without cursor polling.
    }
    if (_kind == 'hyprland') {
      final point = await _request(_path!, 'j/cursorpos', null);
      if (point is! Map) throw const FormatException('Invalid cursor response');
      final x = _number(point['x']), y = _number(point['y']);
      if (x == null || y == null) {
        throw const FormatException('Invalid cursor coordinates');
      }
      for (final raw in _outputs) {
        final sample = parseHyprlandPomoOutput(raw);
        if (sample != null &&
            x >= sample.x! &&
            y >= sample.y! &&
            x < sample.x! + sample.width! &&
            y < sample.y! + sample.height!) {
          return sample;
        }
      }
      return null;
    }
    // Sway delivers workspace/output changes through its event connection.
    return null;
  }

  @override
  Future<void> stop() async {
    _running = false;
    _kind = null;
    await _sway.stop();
    await _kwin.stop();
  }

  @override
  void dispose() {
    unawaited(_sway.stop());
    _kwin.dispose();
  }
}

double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
List<Map> _mapList(Object? value) =>
    value is List ? value.whereType<Map>().toList() : const [];

PomoMonitorSample? parseHyprlandPomoOutput(Map raw) {
  final x = _number(raw['x']), y = _number(raw['y']);
  var width = _number(raw['width']), height = _number(raw['height']);
  final scale = _number(raw['scale']) ?? 1;
  if (x == null ||
      y == null ||
      width == null ||
      height == null ||
      width <= 0 ||
      height <= 0 ||
      scale <= 0) {
    return null;
  }
  if ([1, 3, 5, 7].contains(raw['transform'])) {
    final swap = width;
    width = height;
    height = swap;
  }
  return PomoMonitorSample(
    name: raw['name'] is String ? raw['name'] as String : null,
    x: x,
    y: y,
    width: width / scale,
    height: height / scale,
  );
}

/// One request per short-lived Unix socket; limits prevent unbounded IPC replies.
Future<Object?> requestPomoSocket(
  String path,
  String request,
  int? swayType,
) async {
  final socket = await Socket.connect(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
    timeout: const Duration(milliseconds: 500),
  );
  final result = Completer<List<int>>();
  final bytes = <int>[];
  final subscription = socket.listen(
    (chunk) {
      if (result.isCompleted) return;
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        result.completeError(
          const FormatException('Compositor response too large'),
        );
        return;
      }
      if (swayType != null && bytes.length >= 14) {
        if (ascii.decode(bytes.take(6).toList(), allowInvalid: true) !=
            'i3-ipc') {
          result.completeError(
            const FormatException('Invalid Sway IPC header'),
          );
          return;
        }
        final header = ByteData.sublistView(Uint8List.fromList(bytes), 6, 14);
        final length = header.getUint32(0, Endian.little);
        if (length > 1024 * 1024 ||
            header.getUint32(4, Endian.little) != swayType) {
          result.completeError(
            const FormatException('Invalid Sway IPC response'),
          );
        } else if (bytes.length >= 14 + length) {
          result.complete(bytes.sublist(14, 14 + length));
        }
      }
    },
    onError: (Object error) {
      if (!result.isCompleted) result.completeError(error);
    },
    onDone: () {
      if (!result.isCompleted) {
        if (swayType == null) {
          result.complete(bytes);
        } else {
          result.completeError(
            const FormatException('Truncated Sway response'),
          );
        }
      }
    },
  );
  try {
    final payload = utf8.encode(request);
    if (swayType != null) {
      final header = ByteData(8)
        ..setUint32(0, payload.length, Endian.little)
        ..setUint32(4, swayType, Endian.little);
      socket.add([
        ...ascii.encode('i3-ipc'),
        ...header.buffer.asUint8List(),
        ...payload,
      ]);
    } else {
      socket.add(payload);
    }
    await socket.flush();
    return jsonDecode(
      utf8.decode(
        await result.future.timeout(const Duration(milliseconds: 750)),
      ),
    );
  } finally {
    socket.destroy();
    await subscription.cancel();
  }
}
