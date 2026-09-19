import 'package:pomodoist/data/services/voice/voice_transcription_policy.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/services/voice/pomodoist_voice_controller.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoist/data/services/planning/task_decomposer.dart'
    show fallbackQuickAddTasks;
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/voice/voice_quick_add_state.dart';
import 'package:pomodoist/data/services/voice/voice_capture_service.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

const _voiceSmartModePreferenceKey = 'voice.smartMode';

typedef DecomposeVoiceTasks =
    Future<List<DecomposedTaskDraft>> Function(
      String transcript, {
      required DateTime now,
      required String locale,
      bool smartMode,
    });

/// One instance belongs to the retained overlay host, never to a route or account.
class VoiceQuickAddRepository extends ChangeNotifier {
  VoiceQuickAddRepository({
    required VoiceCaptureService initialController,
    required this.waitForMode,
    required this.effectiveMode,
    required this.replaceController,
    required this.setMode,
    required this.signedIn,
    required this.preferences,
    required this.decomposer,
  }) {
    voiceController = initialController;
    voiceMode =
        supportsVoiceTranscriptionModeSelection(
              isWeb: kIsWeb,
              platform: defaultTargetPlatform,
            ) &&
            initialController is! BackendVoiceController
        ? VoiceTranscriptionMode.system
        : VoiceTranscriptionMode.cloud;
  }

  final Future<void> Function() waitForMode;
  final VoiceTranscriptionMode Function() effectiveMode;
  final VoiceCaptureService Function() replaceController;
  final Future<void> Function(VoiceTranscriptionMode) setMode;
  final bool Function() signedIn;
  final Future<SharedPreferences?> Function() preferences;
  final DecomposeVoiceTasks decomposer;
  String locale = 'en';
  List<DecomposedTaskDraft> drafts = const [];
  int draftRevision = 0;
  void setSaving(bool value) => update(() => saving = value);
  void setError(Object? value) => update(() => error = value);
  VoiceQuickAddState get state => VoiceQuickAddState(
    status: VoiceCaptureStatus.values.byName(status.name),
    transcript: transcript,
    error: error,
    recognitionErrorMessage: recognitionErrorMessage,
    voiceErrorCode: voiceErrorCode,
    restoring: restoring,
    accessBusy: accessBusy,
    analyzing: analyzing,
    saving: saving,
    stopping: stopping,
    captureActive: captureActive,
    smartMode: smartMode,
    amplitudeLevel: amplitudeLevel,
    recordingSecondsRemaining: recordingSecondsRemaining,
    isCapturing: isCapturing,
    isTranscribing: isTranscribing,
    canStart: canStart,
    motionActive: motionActive,
    canUseCloudFallback: canUseCloudFallback,
    needsPermissionRequest: needsPermissionRequest,
    settingsDestination: settingsDestination == null
        ? null
        : VoiceAccessSettings.values.byName(settingsDestination!.name),
    canRetryTranscription: voiceController.canRetryTranscription,
    cloudMode: voiceMode == VoiceTranscriptionMode.cloud,
    drafts: drafts,
    draftRevision: draftRevision,
  );
  bool _disposed = false;
  bool get isActive => !_disposed;

  void update(VoidCallback action) {
    if (_disposed) return;
    action();
    notifyListeners();
  }

  late VoiceCaptureService voiceController;
  late VoiceTranscriptionMode voiceMode;
  VoiceCaptureStatus status = VoiceCaptureStatus.idle;
  StreamSubscription<VoiceCaptureEvent>? subscription;
  StreamSubscription<double>? amplitudeSubscription;
  String transcript = '';
  Object? error;
  String recognitionErrorMessage = "";
  String? voiceErrorCode;
  Map<String, Object?> access = const {};
  bool accessBusy = false;
  bool restoring = true;
  int accessCheck = 0;
  bool analyzing = false;
  bool saving = false;
  bool stopping = false;
  bool captureActive = false;
  bool smartMode = false;
  bool smartModeChanged = false;
  double amplitudeLevel = 0;
  int recordingSecondsRemaining = voiceQuickAddMaxDuration.inSeconds;
  Timer? recordingTimer;

  bool get isCapturing =>
      status == VoiceCaptureStatus.recording ||
      status == VoiceCaptureStatus.requestingPermission;

  bool get isTranscribing => status == VoiceCaptureStatus.transcribing;

  bool get canStart =>
      !restoring &&
      !accessBusy &&
      !captureActive &&
      !isCapturing &&
      !isTranscribing &&
      !analyzing &&
      !saving;

  bool get motionActive =>
      captureActive || isCapturing || isTranscribing || analyzing;

  Future<void> _loadSmartMode() async {
    final prefs = await preferences();
    if (!isActive || smartModeChanged) {
      return;
    }
    update(() {
      smartMode = prefs?.getBool(_voiceSmartModePreferenceKey) ?? false;
    });
  }

  void setSmartMode(bool value) {
    smartModeChanged = true;
    update(() => smartMode = value);
    unawaited(_saveSmartMode(value));
  }

  Future<void> _saveSmartMode(bool value) async {
    final prefs = await preferences();
    await prefs?.setBool(_voiceSmartModePreferenceKey, value);
  }

  void startRecordingCountdown() {
    recordingTimer?.cancel();
    update(() {
      recordingSecondsRemaining = voiceQuickAddMaxDuration.inSeconds;
    });
    recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isActive || status != VoiceCaptureStatus.recording) {
        timer.cancel();
        return;
      }
      update(() {
        if (recordingSecondsRemaining > 0) {
          recordingSecondsRemaining -= 1;
        }
      });
      if (recordingSecondsRemaining == 0) {
        timer.cancel();
      }
    });
  }

  void stopRecordingCountdown() {
    recordingTimer?.cancel();
    recordingTimer = null;
  }

  void startAmplitudeMeter() {
    final previous = amplitudeSubscription;
    if (previous != null) {
      unawaited(previous.cancel());
    }
    amplitudeSubscription = voiceController.amplitudeDbfs.listen((dbfs) {
      if (!isActive ||
          status != VoiceCaptureStatus.recording ||
          !dbfs.isFinite) {
        return;
      }
      update(() {
        amplitudeLevel = ((dbfs + 60) / 60).clamp(0.0, 1.0);
      });
    }, onError: (_) {});
  }

  void stopAmplitudeMeter() {
    final subscription = amplitudeSubscription;
    amplitudeSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (amplitudeLevel != 0) {
      update(() => amplitudeLevel = 0);
    }
  }

  Future<void> _start({bool retry = false}) async {
    if (!canStart) {
      return;
    }
    if (!retry) {
      update(() => accessBusy = true);
      try {
        await _syncVoiceControllerForNewRecording();
      } catch (_) {
        if (isActive) {
          update(() => error = VoiceQuickAddError.general);
        }
        return;
      } finally {
        if (isActive) update(() => accessBusy = false);
      }
      if (!isActive || !canStart) return;
    }
    final languageTag = locale;
    update(() {
      captureActive = true;
      status = retry
          ? VoiceCaptureStatus.transcribing
          : VoiceCaptureStatus.requestingPermission;
      error = null;
      voiceErrorCode = null;
      access = const {};
      ++accessCheck;
      transcript = '';
      analyzing = false;

      drafts = const [];
      draftRevision++;
    });
    stopRecordingCountdown();
    stopAmplitudeMeter();
    final previousSubscription = subscription;
    subscription = null;
    await previousSubscription?.cancel();
    if (!isActive) {
      return;
    }
    try {
      final stream = retry
          ? voiceController.retryTranscription()
          : voiceController.start(
              VoiceCaptureConfig(
                locale: languageTag,
                maxDuration: voiceQuickAddMaxDuration,
              ),
            );
      subscription = stream.listen(
        handleEvent,
        onDone: () {
          if (isActive) {
            stopRecordingCountdown();
            stopAmplitudeMeter();
            update(() {
              captureActive = false;
              if (isCapturing || isTranscribing) {
                status = VoiceCaptureStatus.idle;
              }
            });
          }
        },
      );
    } catch (error) {
      update(() {
        captureActive = false;
        status = VoiceCaptureStatus.error;
        voiceErrorCode = error is VoiceCaptureException ? error.code : null;
        recognitionErrorMessage = error.toString();
        this.error = VoiceQuickAddError.recognition;
      });
    }
  }

  Future<void> _stop() async {
    if (stopping) return;
    update(() => stopping = true);
    try {
      await voiceController.stop();
    } catch (_) {
      if (isActive) update(() => error = VoiceQuickAddError.general);
    } finally {
      if (isActive) update(() => stopping = false);
    }
  }

  void handleEvent(VoiceCaptureEvent event) {
    if (!isActive) {
      return;
    }
    var shouldDecompose = false;
    update(() {
      status = event.status;
      switch (event.status) {
        case VoiceCaptureStatus.completed:
          captureActive = false;
          transcript = event.finalText ?? transcript;
          if (transcript.trim().isNotEmpty) {
            shouldDecompose = true;
          }
        case VoiceCaptureStatus.canceled:
          captureActive = false;
        case VoiceCaptureStatus.error:
        case VoiceCaptureStatus.unsupportedPlatform:
          captureActive = false;
          voiceErrorCode = event.error?.code;
          recognitionErrorMessage = event.error?.message ?? "";
          error = event.error == null ? null : VoiceQuickAddError.recognition;
        case VoiceCaptureStatus.idle:
        case VoiceCaptureStatus.requestingPermission:
        case VoiceCaptureStatus.recording:
        case VoiceCaptureStatus.transcribing:
          break;
      }
    });
    if (event.status == VoiceCaptureStatus.recording) {
      startRecordingCountdown();
      startAmplitudeMeter();
    } else if (event.status == VoiceCaptureStatus.transcribing ||
        event.status == VoiceCaptureStatus.completed ||
        event.status == VoiceCaptureStatus.canceled ||
        event.status == VoiceCaptureStatus.error ||
        event.status == VoiceCaptureStatus.unsupportedPlatform) {
      stopRecordingCountdown();
      stopAmplitudeMeter();
    }
    if (event.status == VoiceCaptureStatus.error) {
      unawaited(_refreshAccess());
    }
    if (shouldDecompose) {
      unawaited(_decomposeTranscript(transcript));
    }
  }

  Future<void> _restoreRecording() async {
    try {
      await waitForMode();
      if (!isActive) return;
      final mode = effectiveVoiceMode;
      if (mode != voiceMode) {
        // Select the saved mode before restoring; opening must not discard audio.
        replaceVoiceController(mode);
      }
      await voiceController.restorePendingRecording();
    } catch (_) {
      if (isActive) error = VoiceQuickAddError.general;
    }
    if (!isActive) return;
    update(() => restoring = false);
    if (voiceController.canRetryTranscription) await _refreshAccess();
  }

  Future<bool> _closeVoice() async {
    if (saving) return false;
    update(() {
      captureActive = false;
      status = VoiceCaptureStatus.canceled;
    });
    try {
      await voiceController.cancel();
      return isActive;
    } catch (_) {
      if (isActive) update(() => error = VoiceQuickAddError.general);
    }
    return false;
  }

  bool get accessRestricted =>
      access['microphone'] == 'restricted' ||
      access['speech'] == 'restricted' ||
      (access.isEmpty &&
          (voiceErrorCode == 'microphone_restricted' ||
              voiceErrorCode == 'speech_authorization_restricted'));

  VoiceTranscriptionMode get effectiveVoiceMode => effectiveMode();

  bool get canUseCloudFallback =>
      access['microphone'] != 'denied' &&
      access['microphone'] != 'restricted' &&
      canOfferCloudTranscriptionFallback(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
        mode: voiceMode,
        signedIn: signedIn(),
        errorCode: voiceErrorCode,
      );

  Future<void> _syncVoiceControllerForNewRecording() async {
    await waitForMode();
    final mode = effectiveVoiceMode;
    if (mode == voiceMode) return;
    await voiceController.cancel();
    if (!isActive) return;
    replaceVoiceController(mode);
  }

  void replaceVoiceController(VoiceTranscriptionMode mode) {
    voiceController = replaceController();
    voiceMode = mode;
  }

  Future<void> _useCloudTranscription() async {
    if (!canStart || !canUseCloudFallback) return;
    update(() => accessBusy = true);
    try {
      await voiceController.cancel();
      await setMode(VoiceTranscriptionMode.cloud);
      if (!isActive) return;
      replaceVoiceController(VoiceTranscriptionMode.cloud);
      update(() {
        error = null;
        voiceErrorCode = null;
      });
    } catch (_) {
      if (isActive) {
        update(() => error = VoiceQuickAddError.general);
      }
      return;
    } finally {
      if (isActive) update(() => accessBusy = false);
    }
    if (isActive) await _start();
  }

  bool get needsPermissionRequest =>
      !accessRestricted &&
      (access['microphone'] == 'notDetermined' ||
          access['speech'] == 'notDetermined');

  VoiceAccessSettings? get settingsDestination {
    if (accessRestricted) return null;
    if (access['microphone'] == 'denied' ||
        voiceErrorCode == 'microphone_denied') {
      return VoiceAccessSettings.microphone;
    }
    if (voiceMode != VoiceTranscriptionMode.system) return null;
    if (access['speech'] == 'denied' ||
        voiceErrorCode == 'speech_authorization_denied' ||
        voiceErrorCode == 'speech_permission_denied') {
      return VoiceAccessSettings.speech;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        (voiceErrorCode == 'speech_dictation_disabled' ||
            voiceErrorCode == 'speech_unavailable' ||
            voiceErrorCode == 'speech_recognition_failed')) {
      return VoiceAccessSettings.dictation;
    }
    return null;
  }

  Future<void> _refreshAccess({bool request = false}) async {
    final check = ++accessCheck;
    try {
      final access = await voiceController.checkAccess(
        locale: locale,
        request: request,
      );
      if (!isActive || check != accessCheck) return;
      update(() {
        this.access = access;
        if (access['microphone'] == 'restricted' ||
            access['speech'] == 'restricted') {
          voiceErrorCode = access['microphone'] == 'restricted'
              ? 'microphone_restricted'
              : 'speech_authorization_restricted';
          error = VoiceQuickAddError.restricted;
        } else if (access['microphone'] == 'denied') {
          voiceErrorCode = 'microphone_denied';
          error = VoiceQuickAddError.microphoneDenied;
        } else if (access['speech'] == 'denied') {
          voiceErrorCode = 'speech_authorization_denied';
          error = VoiceQuickAddError.speechDenied;
        } else if (access['microphone'] == 'authorized' &&
            access['speech'] == 'authorized' &&
            const [
              'microphone_denied',
              'microphone_restricted',
              'speech_authorization_restricted',
              'speech_permission_denied',
              'speech_authorization_denied',
            ].contains(voiceErrorCode)) {
          voiceErrorCode = null;
          error = null;
        }
      });
    } on MissingPluginException {
      // Platforms without Apple Speech have no permission recovery channel.
    } catch (_) {
      // Preserve the actionable recognition error if the status service also fails.
    }
  }

  Future<void> _recoverAccess() async {
    final destination = settingsDestination;
    final request = needsPermissionRequest;
    update(() => accessBusy = true);
    try {
      if (request) {
        await _refreshAccess(request: true);
      } else if (destination != null) {
        final opened = await voiceController.openSettings(destination);
        if (!opened && isActive) {
          update(() => error = VoiceQuickAddError.settings);
        }
      }
    } catch (_) {
      if (isActive) {
        update(() => error = VoiceQuickAddError.settings);
      }
    } finally {
      if (isActive) update(() => accessBusy = false);
    }
  }

  Future<void> _decomposeTranscript(String transcript) async {
    update(() {
      analyzing = true;
      error = null;
      this.drafts = const [];
      draftRevision++;
    });
    List<DecomposedTaskDraft> drafts;
    Object? failure;
    try {
      final tasks = await decomposer(
        transcript,
        now: DateTime.now(),
        locale: locale,
        smartMode: smartMode,
      );
      if (!isActive) {
        return;
      }
      drafts = tasks.isEmpty ? fallbackQuickAddTasks(transcript) : tasks;
    } catch (exception) {
      if (!isActive) {
        return;
      }
      failure = exception is TaskDecompositionException
          ? exception.message
          : VoiceQuickAddError.fallback;
      drafts = fallbackQuickAddTasks(transcript);
    }
    if (!isActive) {
      return;
    }
    update(() {
      error = failure;
      this.drafts = List.unmodifiable(drafts);
      draftRevision++;
      analyzing = false;
    });
  }

  Future<Result<void>> loadSmartMode() =>
      Result.capture(() => _loadSmartMode());
  Future<Result<void>> saveSmartMode(bool value) =>
      Result.capture(() => _saveSmartMode(value));
  Future<Result<void>> start({bool retry = false}) =>
      Result.capture(() => _start(retry: retry));
  Future<Result<void>> stop() => Result.capture(() => _stop());
  Future<Result<void>> restoreRecording() =>
      Result.capture(() => _restoreRecording());
  Future<Result<bool>> closeVoice() => Result.capture(() => _closeVoice());
  Future<Result<void>> syncVoiceControllerForNewRecording() =>
      Result.capture(() => _syncVoiceControllerForNewRecording());
  Future<Result<void>> useCloudTranscription() =>
      Result.capture(() => _useCloudTranscription());
  Future<Result<void>> refreshAccess({bool request = false}) =>
      Result.capture(() => _refreshAccess(request: request));
  Future<Result<void>> recoverAccess() =>
      Result.capture(() => _recoverAccess());
  Future<Result<void>> decomposeTranscript(String transcript) =>
      Result.capture(() => _decomposeTranscript(transcript));

  @override
  void dispose() {
    _disposed = true;
    subscription?.cancel();
    amplitudeSubscription?.cancel();
    recordingTimer?.cancel();
    if (stopping || isTranscribing) {
      unawaited(voiceController.abortTranscription());
    } else if (captureActive || isCapturing) {
      unawaited(voiceController.cancel());
    }
    super.dispose();
  }
}
