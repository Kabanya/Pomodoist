import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'package:pomodoist/utils/result.dart';

/// Device capture and transcription state for one retained voice session.
///
/// Implementations own the recorder/recognizer handle and expose immutable
/// snapshots. Presentation state such as drafts, saving and panel flags does
/// not belong here.
abstract interface class VoiceCaptureRepository {
  VoiceCaptureState get currentState;

  /// The current snapshot followed by later updates, without a subscription
  /// gap. Callers own the returned subscription and cancel it on disposal.
  Stream<VoiceCaptureState> watchState();

  Future<Result<void>> start(String locale, {bool retry = false});
  Future<Result<void>> stop();
  Future<Result<bool>> close();
  Future<Result<void>> restore();
  Future<Result<void>> refreshAccess({
    required String locale,
    bool request = false,
  });
  Future<Result<void>> recoverAccess(String locale);
  Future<Result<void>> useCloudTranscription(String locale);
}
