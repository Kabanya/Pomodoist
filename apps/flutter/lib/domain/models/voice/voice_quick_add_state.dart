import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';

enum VoiceQuickAddError {
  general,
  settings,
  restricted,
  microphoneDenied,
  speechDenied,
  fallback,
  recognition,
}

/// Immutable presentation state for one retained voice quick add overlay.
class VoiceQuickAddState {
  VoiceQuickAddState({
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
    required List<DecomposedTaskDraft> drafts,
    required this.draftRevision,
  }) : drafts = List.unmodifiable(drafts);
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
