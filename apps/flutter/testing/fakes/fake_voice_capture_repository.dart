import 'dart:async';

import 'package:pomodoist/data/repositories/voice/voice_capture_repository.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

/// In-memory [VoiceCaptureRepository] double.
///
/// Every command records its arguments and succeeds unless its
/// `<method>Error` field is set. The snapshot is driven by [emit]: [watchState]
/// replays [currentState] first and then follows the emitted updates.
class FakeVoiceCaptureRepository extends StrictFake
    implements VoiceCaptureRepository {
  /// Snapshot [currentState] answers with.
  @override
  VoiceCaptureState currentState = const VoiceCaptureState(restoring: false);

  /// Value [close] succeeds with.
  bool closeResult = true;

  /// When non-null, the matching method fails with it.
  Object? startError;
  Object? stopError;
  Object? closeError;
  Object? restoreError;
  Object? refreshAccessError;
  Object? recoverAccessError;
  Object? useCloudTranscriptionError;

  /// Arguments of each [start] call.
  final startCalls = <({String locale, bool retry})>[];

  /// Arguments of each [refreshAccess] call.
  final refreshAccessCalls = <({String locale, bool request})>[];

  /// Locales passed to [recoverAccess].
  final recoverAccessCalls = <String>[];

  /// Locales passed to [useCloudTranscription].
  final useCloudTranscriptionCalls = <String>[];

  final stopCalls = <void>[];
  final closeCalls = <void>[];
  final restoreCalls = <void>[];

  final _updates = StreamController<VoiceCaptureState>.broadcast();

  @override
  Stream<VoiceCaptureState> watchState() {
    final controller = StreamController<VoiceCaptureState>();
    controller.add(currentState);
    final subscription = _updates.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
    return controller.stream;
  }

  /// Publishes [state] as the new [currentState] and to [watchState] listeners.
  void emit(VoiceCaptureState state) {
    currentState = state;
    _updates.add(state);
  }

  @override
  Future<Result<void>> start(String locale, {bool retry = false}) async {
    startCalls.add((locale: locale, retry: retry));
    final error = startError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> stop() async {
    stopCalls.add(null);
    final error = stopError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> close() async {
    closeCalls.add(null);
    final error = closeError;
    if (error != null) return Result.error(error, StackTrace.current);
    return Result.ok(closeResult);
  }

  @override
  Future<Result<void>> restore() async {
    restoreCalls.add(null);
    final error = restoreError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> refreshAccess({
    required String locale,
    bool request = false,
  }) async {
    refreshAccessCalls.add((locale: locale, request: request));
    final error = refreshAccessError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> recoverAccess(String locale) async {
    recoverAccessCalls.add(locale);
    final error = recoverAccessError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> useCloudTranscription(String locale) async {
    useCloudTranscriptionCalls.add(locale);
    final error = useCloudTranscriptionError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }
}
