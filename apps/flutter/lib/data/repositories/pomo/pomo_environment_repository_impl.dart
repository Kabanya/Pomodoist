import 'dart:async';

import 'package:pomodoist/data/repositories/pomo/pomo_environment_codec.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_environment_repository.dart';
import 'package:pomodoist/data/services/platform/pomo_environment_gateway.dart';
import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';
import 'package:pomodoist/data/services/platform/pomo_follow_transport_factory.dart';
import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

class LinuxPomoEnvironmentRepository implements PomoEnvironmentRepository {
  LinuxPomoEnvironmentRepository({
    PomoNativeEnvironmentGateway? native,
    PomoFollowTransport? followTransport,
    Duration refreshInterval = const Duration(seconds: 2),
    Duration followInterval = const Duration(milliseconds: 100),
  }) : _native = native ?? const MethodChannelPomoEnvironmentGateway(),
       _transport = followTransport ?? createPomoFollowTransport(),
       _refreshInterval = refreshInterval,
       _followInterval = followInterval;

  final PomoNativeEnvironmentGateway _native;
  final PomoFollowTransport _transport;
  final Duration _refreshInterval, _followInterval;
  final _changes = StreamController<PomoEnvironment>.broadcast(sync: true);
  PomoEnvironment _state = const PomoEnvironment();
  Timer? _refreshTimer, _followTimer;
  Future<void>? _initialized;
  Future<void> _lifecycle = Future.value();
  Future<void> _environmentQueue = Future.value();
  bool _nativeFollowing = false;
  bool _disposed = false,
      _following = false,
      _refreshing = false,
      _sampling = false;
  String? _activeKey;
  PomoMonitorSample? _lastSample;
  int _generation = 0;

  @override
  PomoEnvironment get state => _state;
  @override
  Stream<PomoEnvironment> get changes => _changes.stream;

  @override
  Future<void> initialize() => _initialized ??= _initialize();

  Future<void> _initialize() async {
    if (_disposed) return;
    await _refresh();
    if (!_disposed) {
      _refreshTimer = Timer.periodic(
        _refreshInterval,
        (_) => unawaited(_refresh()),
      );
    }
  }

  Future<void> _refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      await _queueEnvironment(_native.environment);
    } catch (_) {
      if (!_disposed) {
        _publish(
          _state.copyWith(
            checking: false,
            available: false,
            followSource: PomoFollowSource.none,
            reason: 'The desktop connection is unavailable.',
          ),
        );
        await _syncFollowing();
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  Future<void> gnomeExtensionStatus() =>
      _queueEnvironment(_native.gnomeExtensionStatus);
  @override
  Future<void> installGnomeExtension() =>
      _queueEnvironment(_native.installGnomeExtension);
  @override
  Future<void> enableGnomeExtension() =>
      _queueEnvironment(_native.enableGnomeExtension);

  Future<void> _queueEnvironment(Future<Object?> Function() read) {
    final next = _environmentQueue.then((_) => _updateEnvironment(read));
    _environmentQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _updateEnvironment(Future<Object?> Function() read) async {
    if (_disposed) return;
    var next = parsePomoEnvironment(await read());
    if (_disposed) return;
    var source = PomoFollowSource.none;
    if (next.available) {
      if (next.usesGnomeShell || next.backend.toLowerCase() == 'x11') {
        source = next.followSource;
      } else {
        try {
          source = await _transport.probe(next);
        } catch (_) {
          // Retry on the next environment refresh.
        }
      }
    }
    if (_disposed) return;
    final sameCoordinates = next.placementBackend == _state.placementBackend;
    if (!sameCoordinates) _lastSample = null;
    final previousId = !sameCoordinates
        ? null
        : _following && _lastSample != null
        ? mapPomoMonitor(_lastSample!, next.displays) ?? _state.userDisplayId
        : _state.userDisplayId;
    next = next.copyWith(
      followSource: source,
      userDisplayId: next.displays.any((d) => d.id == previousId)
          ? previousId
          : null,
      clearUserDisplay:
          !next.available || !next.displays.any((d) => d.id == previousId),
    );
    _publish(next);
    await _syncFollowing();
  }

  Future<void> _stopAdapters() async {
    if (_nativeFollowing) {
      // Clear ownership before awaiting so failed/disconnected leases retry safely.
      _nativeFollowing = false;
      try {
        await _native.setFollowing(false);
      } catch (_) {
        /* Owner may have vanished. */
      }
    }
    await _transport.stop();
  }

  @override
  Future<void> startFollowing() async {
    if (_disposed) return;
    _following = true;
    await initialize();
    await _syncFollowing();
  }

  @override
  Future<void> stopFollowing() async {
    _following = false;
    _lastSample = null;
    // Invalidate callbacks immediately, before waiting for in-flight transport I/O.
    ++_generation;
    _followTimer?.cancel();
    _followTimer = null;
    await _syncFollowing();
  }

  Future<void> _syncFollowing() {
    final next = _lifecycle.then((_) async {
      final key =
          !_disposed && _following && _state.available && _state.canFollow
          ? '${_state.placementBackend.name}:${_state.backend}:${_state.desktop}:${_state.followSource.name}'
          : null;
      if (key == _activeKey) return;
      final generation = ++_generation;
      _followTimer?.cancel();
      _followTimer = null;
      _activeKey = null;
      await _stopAdapters();
      if (key == null || _disposed || !_following) return;
      try {
        if (_state.usesGnomeShell) {
          _nativeFollowing = true;
          await _native.setFollowing(true);
        } else if (_state.backend.toLowerCase() != 'x11') {
          await _transport.start(
            _state,
            (sample) => _accept(sample, generation),
            () => _disconnected(generation),
          );
        }
        if (_disposed || !_following || generation != _generation) {
          await _stopAdapters();
          return;
        }
        _activeKey = key;
        await _sample(generation);
        if (generation == _generation && _activeKey != null) {
          _followTimer = Timer.periodic(
            _followInterval,
            (_) => unawaited(_sample(generation)),
          );
        }
      } catch (_) {
        _disconnected(generation);
      }
    });
    _lifecycle = next.catchError((Object _) {});
    return next;
  }

  Future<void> _sample(int generation) async {
    if (_disposed || !_following || generation != _generation || _sampling) {
      return;
    }
    _sampling = true;
    try {
      PomoMonitorSample? sample;
      if (_state.usesGnomeShell || _state.backend.toLowerCase() == 'x11') {
        final raw = await _native.cursor();
        if (raw is Map) {
          final x = pomoFiniteNumber(raw['x']), y = pomoFiniteNumber(raw['y']);
          if (x != null && y != null) {
            sample = PomoMonitorSample(cursorX: x, cursorY: y);
          }
        }
        if (sample == null) throw StateError('Cursor unavailable');
      } else {
        sample = await _transport.sample();
      }
      if (sample != null) _accept(sample, generation);
    } catch (_) {
      _disconnected(generation);
    } finally {
      _sampling = false;
    }
  }

  void _accept(PomoMonitorSample sample, int generation) {
    if (_disposed || !_following || generation != _generation) return;
    _lastSample = sample;
    final id = mapPomoMonitor(sample, _state.displays);
    if (id != null && id != _state.userDisplayId) {
      _publish(_state.copyWith(userDisplayId: id));
    }
  }

  void _disconnected(int generation) {
    if (_disposed || generation != _generation) return;
    ++_generation;
    _lastSample = null;
    _activeKey = null;
    _followTimer?.cancel();
    _followTimer = null;
    _publish(
      _state.copyWith(
        followSource: PomoFollowSource.none,
        clearUserDisplay: true,
      ),
    );
    // A failed adapter owns temporary resources until this cleanup finishes.
    _lifecycle = _lifecycle
        .then((_) => _stopAdapters())
        .catchError((Object _) {});
  }

  void _publish(PomoEnvironment value) {
    if (_disposed) return;
    _state = value;
    _changes.add(value);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _following = false;
    ++_generation;
    _refreshTimer?.cancel();
    _followTimer?.cancel();
    unawaited(
      _lifecycle
          .then((_) async {
            try {
              await _stopAdapters();
            } finally {
              _transport.dispose();
            }
          })
          .catchError((Object _) {}),
    );
    unawaited(_changes.close());
  }
}
