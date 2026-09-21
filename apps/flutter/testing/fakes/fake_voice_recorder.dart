import 'dart:async';

import 'package:pomodoist/data/services/voice/voice_recording.dart';

import 'strict_fake.dart';

/// In-memory [VoiceRecorder] double.
///
/// [hasPermission] answers from [permission], [amplitudeDbfs] emits
/// [amplitudeLevel], and [stop] answers with [stopResult] or, when that is
/// null, the last path passed to [start].
class FakeVoiceRecorder extends StrictFake implements VoiceRecorder {
  /// Answer of [hasPermission].
  bool permission = true;

  /// Level emitted by [amplitudeDbfs].
  double amplitudeLevel = 0;

  /// Value [stop] succeeds with. When null, [stop] returns the last started
  /// path instead.
  String? stopResult;

  /// When set, [stop] stays pending until the completer resolves.
  Completer<String?>? stopGate;

  /// Requests passed to [hasPermission].
  final hasPermissionCalls = <({bool request})>[];

  /// Paths passed to [start].
  final startCalls = <String>[];

  final stopCalls = <void>[];
  final cancelCalls = <void>[];
  final disposeCalls = <void>[];

  @override
  Stream<double> get amplitudeDbfs => Stream.value(amplitudeLevel);

  @override
  Future<bool> hasPermission({bool request = true}) async {
    hasPermissionCalls.add((request: request));
    return permission;
  }

  @override
  Future<void> start(String path) async {
    startCalls.add(path);
  }

  @override
  Future<String?> stop() async {
    stopCalls.add(null);
    final gate = stopGate;
    if (gate != null) return gate.future;
    return stopResult ?? (startCalls.isEmpty ? null : startCalls.last);
  }

  @override
  Future<void> cancel() async {
    cancelCalls.add(null);
  }

  @override
  Future<void> dispose() async {
    disposeCalls.add(null);
  }
}
