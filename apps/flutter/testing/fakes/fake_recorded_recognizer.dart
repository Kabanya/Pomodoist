import 'package:app_voice/app_voice.dart';

/// Double for [RecordedVoiceRecognizer] replaying a fixed transcript.
///
/// [start] succeeds unless [startError] is set, [stop] and [retryTranscription]
/// return [transcript], and the call counters record what the controller did.
/// Setting [pendingRecording] models a recording that outlived the previous app
/// session: the controller can restore and retry it, which clears the flag.
class FakeRecordedRecognizer extends RecordedVoiceRecognizer
    implements RecordedVoiceAmplitudeSource {
  FakeRecordedRecognizer({
    required this.transcript,
    this.amplitudeDbfs = const Stream<double>.empty(),
    this.startError,
    this.pendingRecording = false,
  });

  /// Returned by [stop] and [retryTranscription].
  final VoiceRecognitionTranscript transcript;

  @override
  final Stream<double> amplitudeDbfs;

  /// When non-null, [start] throws it.
  final Object? startError;

  /// Whether a recording is available to restore or retry.
  bool pendingRecording;

  /// Number of [start] calls.
  int startCalls = 0;

  /// Number of [stop] calls.
  int stopCalls = 0;

  /// Number of [cancel] calls.
  int cancelCalls = 0;

  /// Number of [retryTranscription] calls.
  int retryCalls = 0;

  /// When non-null, [cancel] awaits it before returning.
  Future<void>? cancelWait;

  @override
  bool get canRetryTranscription => pendingRecording;

  @override
  Future<bool> restorePendingRecording() async => pendingRecording;

  @override
  Future<VoiceRecognitionTranscript> retryTranscription() async {
    retryCalls++;
    pendingRecording = false;
    return transcript;
  }

  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    startCalls++;
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) async {
    stopCalls++;
    return transcript;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    pendingRecording = false;
    await cancelWait;
  }

  @override
  void dispose() {}
}
