import 'package:app_voice/app_voice.dart';
import 'package:pomodoist/domain/models/voice/voice_quick_add_state.dart';

abstract interface class VoiceCaptureService {
  bool get canRetryTranscription;
  Stream<double> get amplitudeDbfs;
  Future<bool> restorePendingRecording();
  Stream<VoiceCaptureEvent> start(VoiceCaptureConfig config);
  Stream<VoiceCaptureEvent> retryTranscription();
  Future<void> stop();
  Future<void> cancel();
  Future<void> abortTranscription();
  Future<Map<String, Object?>> checkAccess({
    String? locale,
    bool request = false,
  });
  Future<bool> openSettings(VoiceAccessSettings destination);
  void dispose();
}

class AppVoiceCaptureService implements VoiceCaptureService {
  const AppVoiceCaptureService(this._controller);
  final VoiceRecognitionController _controller;

  @override
  bool get canRetryTranscription => _controller.canRetryTranscription;
  @override
  Stream<double> get amplitudeDbfs => _controller.amplitudeDbfs;
  @override
  Future<bool> restorePendingRecording() =>
      _controller.restorePendingRecording();
  @override
  Stream<VoiceCaptureEvent> start(VoiceCaptureConfig config) {
    try {
      return _events(
        _controller.start(
          VoiceRecognitionConfig(
            locale: config.locale,
            maxDuration: config.maxDuration,
          ),
        ),
      );
    } on VoiceRecognitionException catch (error) {
      throw VoiceCaptureException(error.code, error.message);
    }
  }

  @override
  Stream<VoiceCaptureEvent> retryTranscription() {
    try {
      return _events(_controller.retryTranscription());
    } on VoiceRecognitionException catch (error) {
      throw VoiceCaptureException(error.code, error.message);
    }
  }

  Stream<VoiceCaptureEvent> _events(Stream<VoiceRecognitionEvent> events) =>
      events.map(
        (event) => VoiceCaptureEvent(
          status: VoiceCaptureStatus.values.byName(event.status.name),
          finalText: event.finalText,
          error: event.error == null
              ? null
              : VoiceCaptureError(
                  code: event.error!.code,
                  message: event.error!.message,
                ),
        ),
      );
  @override
  Future<void> stop() => _controller.stop();
  @override
  Future<void> cancel() => _controller.cancel();
  @override
  Future<void> abortTranscription() => _controller.abortTranscription();
  @override
  Future<Map<String, Object?>> checkAccess({
    String? locale,
    bool request = false,
  }) => _controller.checkAccess(locale: locale, request: request);
  @override
  Future<bool> openSettings(VoiceAccessSettings destination) => _controller
      .openSettings(VoiceSettingsDestination.values.byName(destination.name));
  @override
  void dispose() => _controller.dispose();
}
