import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_environment_repository_impl.dart';
import 'package:pomodoist/data/services/platform/pomo_environment_gateway.dart';
import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';
import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

import 'pomo_environment_test.dart' show environmentPayload;

class Native implements PomoNativeEnvironmentGateway {
  Object? payload = environmentPayload();
  Object? point = {'x': -10, 'y': 20};
  int reads = 0, cursors = 0;
  @override
  Future<Object?> environment() async {
    ++reads;
    return payload;
  }

  @override
  Future<Object?> cursor() async {
    ++cursors;
    return point;
  }
}

class Transport implements PomoFollowTransport {
  PomoFollowSource source = PomoFollowSource.cursor;
  int starts = 0, samples = 0, stops = 0, disposed = 0;
  bool fail = false, failStop = false;
  PomoMonitorSample? result = const PomoMonitorSample(name: 'DP-1');
  Completer<void>? pendingStart;
  void Function(PomoMonitorSample)? deliver;
  void Function()? disconnect;
  @override
  Future<PomoFollowSource> probe(PomoEnvironment environment) async => source;
  @override
  Future<void> start(
    PomoEnvironment environment,
    void Function(PomoMonitorSample) onSample,
    void Function() onDisconnect,
  ) async {
    ++starts;
    deliver = onSample;
    disconnect = onDisconnect;
    await pendingStart?.future;
  }

  @override
  Future<PomoMonitorSample?> sample() async {
    ++samples;
    if (fail) throw StateError('Socket closed');
    return result;
  }

  @override
  Future<void> stop() async {
    ++stops;
    if (failStop) throw StateError('Cleanup disconnected');
  }

  @override
  void dispose() {
    ++disposed;
  }
}

void main() {
  test(
    'early compositor reports are remapped after native topology catches up',
    () {
      fakeAsync((async) {
        final native = Native()
          ..payload = environmentPayload(backend: 'wayland');
        final transport = Transport()..result = null;
        final repository = LinuxPomoEnvironmentRepository(
          native: native,
          followTransport: transport,
        );
        unawaited(repository.startFollowing());
        async.flushMicrotasks();
        transport.deliver!(
          const PomoMonitorSample(
            name: 'DVI-1',
            x: 2560,
            y: 0,
            width: 1280,
            height: 720,
          ),
        );
        expect(repository.state.userDisplayId, isNull);
        final payload = environmentPayload(backend: 'wayland');
        (payload['displays'] as List).add({
          'id': 'native-new',
          'name': 'DVI-1',
          'x': 2560,
          'y': 0,
          'width': 1280,
          'height': 720,
        });
        native.payload = payload;
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(repository.state.userDisplayId, 'native-new');
        repository.dispose();
        async.flushMicrotasks();
      });
    },
  );

  test('dispose releases transport even if its final stop fails', () {
    fakeAsync((async) {
      final native = Native(), transport = Transport();
      final repository = LinuxPomoEnvironmentRepository(
        native: native,
        followTransport: transport,
      );
      unawaited(repository.initialize());
      async.flushMicrotasks();
      transport.failStop = true;
      repository.dispose();
      async.flushMicrotasks();
      expect(transport.disposed, 1);
    });
  });

  test(
    'topology refreshes every two seconds without hidden cursor polling',
    () {
      fakeAsync((async) {
        final native = Native(), transport = Transport();
        final repository = LinuxPomoEnvironmentRepository(
          native: native,
          followTransport: transport,
        );
        unawaited(repository.initialize());
        async.flushMicrotasks();
        expect(repository.state.available, isTrue);
        expect(native.reads, 1);
        expect(native.cursors, 0);
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(native.reads, 3);
        expect(native.cursors, 0);
        expect(transport.starts, 0);
        repository.dispose();
        async.flushMicrotasks();
        expect(transport.disposed, 1);
        async.elapse(const Duration(seconds: 4));
        expect(native.reads, 3);
      });
    },
  );

  test('X11 starts only while following and releases on stop', () {
    fakeAsync((async) {
      final native = Native(), transport = Transport();
      final repository = LinuxPomoEnvironmentRepository(
        native: native,
        followTransport: transport,
      );
      unawaited(repository.startFollowing());
      async.flushMicrotasks();
      expect(repository.state.userDisplayId, 'native-left');
      expect(native.cursors, 1);
      expect(transport.starts, 0);
      native.point = {'x': 10, 'y': 20};
      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(repository.state.userDisplayId, 'native-right');
      unawaited(repository.stopFollowing());
      async.flushMicrotasks();
      final count = native.cursors;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(native.cursors, count);
      repository.dispose();
      async.flushMicrotasks();
    });
  });

  test('Wayland probes real adapter and reconnects after failed sample', () {
    fakeAsync((async) {
      final native = Native()..payload = environmentPayload(backend: 'wayland');
      final transport = Transport();
      final repository = LinuxPomoEnvironmentRepository(
        native: native,
        followTransport: transport,
      );
      unawaited(repository.startFollowing());
      async.flushMicrotasks();
      expect(repository.state.userDisplayId, 'native-right');
      expect(transport.starts, 1);
      expect(native.cursors, 0);
      transport.fail = true;
      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(repository.state.canFollow, isFalse);
      expect(repository.state.userDisplayId, isNull);
      transport.fail = false;
      async.elapse(const Duration(milliseconds: 1900));
      async.flushMicrotasks();
      expect(repository.state.canFollow, isTrue);
      expect(transport.starts, 2);
      expect(repository.state.userDisplayId, 'native-right');
      repository.dispose();
      async.flushMicrotasks();
    });
  });

  test('fixed-monitor sessions never start unavailable adapters', () {
    fakeAsync((async) {
      final native = Native()..payload = environmentPayload(backend: 'wayland');
      final transport = Transport()..source = PomoFollowSource.none;
      final repository = LinuxPomoEnvironmentRepository(
        native: native,
        followTransport: transport,
      );
      unawaited(repository.startFollowing());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(repository.state.available, isTrue);
      expect(repository.state.canFollow, isFalse);
      expect(transport.starts, 0);
      expect(transport.samples, 0);
      repository.dispose();
      async.flushMicrotasks();
    });
  });

  test('stop during async start ignores late reports and releases helper', () {
    fakeAsync((async) {
      final native = Native()..payload = environmentPayload(backend: 'wayland');
      final transport = Transport()..pendingStart = Completer<void>();
      final repository = LinuxPomoEnvironmentRepository(
        native: native,
        followTransport: transport,
      );
      unawaited(repository.startFollowing());
      async.flushMicrotasks();
      unawaited(repository.stopFollowing());
      async.flushMicrotasks();
      transport.deliver!(const PomoMonitorSample(name: 'DP-1'));
      expect(repository.state.userDisplayId, isNull);
      transport.pendingStart!.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(transport.samples, 0);
      expect(transport.stops, greaterThanOrEqualTo(2));
      repository.dispose();
      async.flushMicrotasks();
    });
  });

  test('removed monitor clears candidate on the next topology refresh', () {
    fakeAsync((async) {
      final native = Native(), transport = Transport();
      final repository = LinuxPomoEnvironmentRepository(
        native: native,
        followTransport: transport,
      );
      unawaited(repository.startFollowing());
      async.flushMicrotasks();
      expect(repository.state.userDisplayId, 'native-left');
      final payload = environmentPayload();
      (payload['displays'] as List).removeAt(0);
      native.payload = payload;
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(repository.state.userDisplayId, isNull);
      expect(repository.state.primaryDisplayId, 'native-right');
      repository.dispose();
      async.flushMicrotasks();
    });
  });
}
