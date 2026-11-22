import 'package:pomodoist/domain/models/settings/custom_model_config.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

enum VoiceQuickAddError {
  general,
  settings,
  preference,
  restricted,
  microphoneDenied,
  speechDenied,
  fallback,
  customAnalysis,
  customAccess,
  customSetup,
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
    this.transcriptionMode = VoiceTranscriptionMode.cloud,
    this.transcriptionModeSelectable = false,
    this.cloudTranscriptionAvailable = false,
    this.usesDownloadableVoiceModel = false,
    this.customHost,
    this.taskRouteReady = false,
    required List<DecomposedTaskDraft> drafts,
    required this.draftRevision,
  }) : drafts = List.unmodifiable(drafts);
  final VoiceCaptureStatus status;
  final String transcript;
  final Object? error;
  bool get canUseTranscriptAsTask =>
      !analyzing &&
      transcript.trim().isNotEmpty &&
      (error is ModelCheck ||
          error == VoiceQuickAddError.customAnalysis ||
          error == VoiceQuickAddError.customAccess);
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
  final VoiceTranscriptionMode transcriptionMode;
  final bool transcriptionModeSelectable;
  final bool cloudTranscriptionAvailable;
  final bool usesDownloadableVoiceModel;
  final String? customHost;
  final bool taskRouteReady;
  bool get canRecord => canStart && taskRouteReady;
  final List<DecomposedTaskDraft> drafts;
  final int draftRevision;
}
