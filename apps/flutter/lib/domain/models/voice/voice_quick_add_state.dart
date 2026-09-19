import 'package:pomodoist/domain/models/planning/task_decomposition.dart';

const voiceQuickAddMaxDuration = Duration(minutes: 5);

enum VoiceQuickAddError {
  general,
  settings,
  restricted,
  microphoneDenied,
  speechDenied,
  fallback,
  recognition,
}

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

class VoiceQuickAddState {
  const VoiceQuickAddState({
    required this.status,
    required this.transcript,
    required this.error,
    required this.recognitionErrorMessage,
    required this.voiceErrorCode,
    required this.restoring,
    required this.accessBusy,
    required this.analyzing,
    required this.saving,
    required this.stopping,
    required this.captureActive,
    required this.smartMode,
    required this.amplitudeLevel,
    required this.recordingSecondsRemaining,
    required this.isCapturing,
    required this.isTranscribing,
    required this.canStart,
    required this.motionActive,
    required this.canUseCloudFallback,
    required this.needsPermissionRequest,
    required this.settingsDestination,
    required this.canRetryTranscription,
    required this.cloudMode,
    required this.drafts,
    required this.draftRevision,
  });
  final VoiceCaptureStatus status;
  final String transcript;
  final Object? error;
  final String recognitionErrorMessage;
  final String? voiceErrorCode;
  final bool restoring;
  final bool accessBusy;
  final bool analyzing;
  final bool saving;
  final bool stopping;
  final bool captureActive;
  final bool smartMode;
  final double amplitudeLevel;
  final int recordingSecondsRemaining;
  final bool isCapturing;
  final bool isTranscribing;
  final bool canStart;
  final bool motionActive;
  final bool canUseCloudFallback;
  final bool needsPermissionRequest;
  final VoiceAccessSettings? settingsDestination;
  final bool canRetryTranscription;
  final bool cloudMode;
  final List<DecomposedTaskDraft> drafts;
  final int draftRevision;
}
