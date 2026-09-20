const voiceQuickAddMaxDuration = Duration(minutes: 5);

enum VoiceCaptureStatus {
  idle,
  requestingPermission,
  recording,
  transcribing,
  completed,
  canceled,
  error,
  unsupportedPlatform,
}

enum VoiceAccessSettings { microphone, speech, dictation }

/// Capture-side failure values; presentation maps these to user-facing errors.
enum VoiceCaptureFailure {
  general,
  settings,
  restricted,
  microphoneDenied,
  speechDenied,
  recognition,
}

class VoiceCaptureConfig {
  const VoiceCaptureConfig({
    this.locale,
    this.maxDuration = const Duration(seconds: 59),
  });
  final String? locale;
  final Duration maxDuration;
}

class VoiceCaptureError {
  const VoiceCaptureError({required this.code, required this.message});
  final String code;
  final String message;
}

class VoiceCaptureEvent {
  const VoiceCaptureEvent({required this.status, this.finalText, this.error});
  final VoiceCaptureStatus status;
  final String? finalText;
  final VoiceCaptureError? error;
}

class VoiceCaptureException implements Exception {
  const VoiceCaptureException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Immutable device capture snapshot for one voice session.
class VoiceCaptureState {
  const VoiceCaptureState({
    this.status = VoiceCaptureStatus.idle,
    this.transcript = '',
    this.failure,
    this.recognitionErrorMessage = '',
    this.voiceErrorCode,
    this.restoring = true,
    this.accessBusy = false,
    this.stopping = false,
    this.capturing = false,
    this.amplitudeLevel = 0,
    this.recordingSecondsRemaining = 300,
    this.canRetryTranscription = false,
    this.canUseCloudFallback = false,
    this.needsPermissionRequest = false,
    this.settingsDestination,
    this.cloudMode = false,
  });

  final VoiceCaptureStatus status;
  final String transcript;
  final VoiceCaptureFailure? failure;
  final String recognitionErrorMessage;
  final String? voiceErrorCode;
  final bool restoring;
  final bool accessBusy;
  final bool stopping;
  final bool capturing;
  final double amplitudeLevel;
  final int recordingSecondsRemaining;
  final bool canRetryTranscription;
  final bool canUseCloudFallback;
  final bool needsPermissionRequest;
  final VoiceAccessSettings? settingsDestination;
  final bool cloudMode;

  bool get isCapturing =>
      status == VoiceCaptureStatus.recording ||
      status == VoiceCaptureStatus.requestingPermission;

  bool get isTranscribing => status == VoiceCaptureStatus.transcribing;

  bool get motionActive => capturing || isCapturing || isTranscribing;

  bool get canStart =>
      !restoring &&
      !accessBusy &&
      !capturing &&
      !isCapturing &&
      !isTranscribing;
}
