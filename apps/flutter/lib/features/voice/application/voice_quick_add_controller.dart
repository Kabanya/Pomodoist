import '../data/pomodoist_voice_controller.dart';
import 'dart:async';

import 'package:app_voice/app_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../planning/data/task_decomposer.dart';
import '../data/voice_transcription_mode.dart';

const voiceQuickAddMaxDuration = Duration(minutes: 5);
const _voiceSmartModePreferenceKey = 'voice.smartMode';

enum VoiceQuickAddError {
  general,
  settings,
  restricted,
  microphoneDenied,
  speechDenied,
  fallback,
  recognition,
}

/// One instance belongs to the retained overlay host, never to a route or account.
class VoiceQuickAddController extends ChangeNotifier {
  VoiceQuickAddController({
    required VoiceRecognitionController initialController,
    required this.waitForMode,
    required this.effectiveMode,
    required this.replaceController,
    required this.setMode,
    required this.signedIn,
    required this.preferences,
    required this.decomposer,
    required this.locale,
    required this.onDrafts,
    required this.onAnalysisStart,
    required this.onAnalysisFinish,
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
  final VoiceRecognitionController Function() replaceController;
  final Future<void> Function(VoiceTranscriptionMode) setMode;
  final bool Function() signedIn;
  final Future<SharedPreferences?> Function() preferences;
  final TaskDecomposer Function() decomposer;
  final String Function() locale;
  final void Function(List<DecomposedTaskDraft>) onDrafts;
  final VoidCallback onAnalysisStart;
  final Future<void> Function() onAnalysisFinish;
  bool _disposed = false;
  bool get isActive => !_disposed;

  void update(VoidCallback action) {
    if (_disposed) return;
    action();
    notifyListeners();
  }

  late VoiceRecognitionController voiceController;
  late VoiceTranscriptionMode voiceMode;
  VoiceRecognitionStatus status = VoiceRecognitionStatus.idle;
  StreamSubscription<VoiceRecognitionEvent>? subscription;
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
      status == VoiceRecognitionStatus.recording ||
      status == VoiceRecognitionStatus.requestingPermission;

  bool get isTranscribing => status == VoiceRecognitionStatus.transcribing;

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

  Future<void> loadSmartMode() async {
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
    unawaited(saveSmartMode(value));
  }

  Future<void> saveSmartMode(bool value) async {
    final prefs = await preferences();
    await prefs?.setBool(_voiceSmartModePreferenceKey, value);
  }

  void startRecordingCountdown() {
    recordingTimer?.cancel();
    update(() {
      recordingSecondsRemaining = voiceQuickAddMaxDuration.inSeconds;
    });
    recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isActive || status != VoiceRecognitionStatus.recording) {
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
          status != VoiceRecognitionStatus.recording ||
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

  Future<void> start({bool retry = false}) async {
    if (!canStart) {
      return;
    }
    if (!retry) {
      update(() => accessBusy = true);
      try {
        await syncVoiceControllerForNewRecording();
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
    final languageTag = locale();
    update(() {
      captureActive = true;
      status = retry
          ? VoiceRecognitionStatus.transcribing
          : VoiceRecognitionStatus.requestingPermission;
      error = null;
      voiceErrorCode = null;
      access = const {};
      ++accessCheck;
      transcript = '';
      analyzing = false;

      onDrafts(const <DecomposedTaskDraft>[]);
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
              VoiceRecognitionConfig(
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
                status = VoiceRecognitionStatus.idle;
              }
            });
          }
        },
      );
    } catch (error) {
      update(() {
        captureActive = false;
        status = VoiceRecognitionStatus.error;
        voiceErrorCode = error is VoiceRecognitionException ? error.code : null;
        recognitionErrorMessage = error.toString();
        this.error = VoiceQuickAddError.recognition;
      });
    }
  }

  Future<void> stop() async {
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

  void handleEvent(VoiceRecognitionEvent event) {
    if (!isActive) {
      return;
    }
    var shouldDecompose = false;
    update(() {
      status = event.status;
      switch (event.status) {
        case VoiceRecognitionStatus.completed:
          captureActive = false;
          transcript = event.finalText ?? transcript;
          if (transcript.trim().isNotEmpty) {
            shouldDecompose = true;
          }
        case VoiceRecognitionStatus.canceled:
          captureActive = false;
        case VoiceRecognitionStatus.error:
        case VoiceRecognitionStatus.unsupportedPlatform:
          captureActive = false;
          voiceErrorCode = event.error?.code;
          recognitionErrorMessage = event.error?.message ?? "";
          error = event.error == null ? null : VoiceQuickAddError.recognition;
        case VoiceRecognitionStatus.idle:
        case VoiceRecognitionStatus.requestingPermission:
        case VoiceRecognitionStatus.recording:
        case VoiceRecognitionStatus.transcribing:
          break;
      }
    });
    if (event.status == VoiceRecognitionStatus.recording) {
      startRecordingCountdown();
      startAmplitudeMeter();
    } else if (event.status == VoiceRecognitionStatus.transcribing ||
        event.status == VoiceRecognitionStatus.completed ||
        event.status == VoiceRecognitionStatus.canceled ||
        event.status == VoiceRecognitionStatus.error ||
        event.status == VoiceRecognitionStatus.unsupportedPlatform) {
      stopRecordingCountdown();
      stopAmplitudeMeter();
    }
    if (event.status == VoiceRecognitionStatus.error) {
      unawaited(refreshAccess());
    }
    if (shouldDecompose) {
      unawaited(decomposeTranscript(transcript));
    }
  }

  Future<void> restoreRecording() async {
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
    if (voiceController.canRetryTranscription) await refreshAccess();
  }

  Future<bool> closeVoice() async {
    if (saving) return false;
    update(() {
      captureActive = false;
      status = VoiceRecognitionStatus.canceled;
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

  Future<void> syncVoiceControllerForNewRecording() async {
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

  Future<void> useCloudTranscription() async {
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
    if (isActive) await start();
  }

  bool get needsPermissionRequest =>
      !accessRestricted &&
      (access['microphone'] == 'notDetermined' ||
          access['speech'] == 'notDetermined');

  VoiceSettingsDestination? get settingsDestination {
    if (accessRestricted) return null;
    if (access['microphone'] == 'denied' ||
        voiceErrorCode == 'microphone_denied') {
      return VoiceSettingsDestination.microphone;
    }
    if (voiceMode != VoiceTranscriptionMode.system) return null;
    if (access['speech'] == 'denied' ||
        voiceErrorCode == 'speech_authorization_denied' ||
        voiceErrorCode == 'speech_permission_denied') {
      return VoiceSettingsDestination.speech;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        (voiceErrorCode == 'speech_dictation_disabled' ||
            voiceErrorCode == 'speech_unavailable' ||
            voiceErrorCode == 'speech_recognition_failed')) {
      return VoiceSettingsDestination.dictation;
    }
    return null;
  }

  Future<void> refreshAccess({bool request = false}) async {
    final check = ++accessCheck;
    try {
      final access = await voiceController.checkAccess(
        locale: locale(),
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

  Future<void> recoverAccess() async {
    final destination = settingsDestination;
    final request = needsPermissionRequest;
    update(() => accessBusy = true);
    try {
      if (request) {
        await refreshAccess(request: true);
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

  Future<void> decomposeTranscript(String transcript) async {
    update(() {
      analyzing = true;
      error = null;
      onDrafts(const <DecomposedTaskDraft>[]);
    });
    onAnalysisStart();
    List<DecomposedTaskDraft> drafts;
    Object? failure;
    try {
      final tasks = await decomposer().decompose(
        transcript,
        now: DateTime.now(),
        locale: locale(),
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
    await onAnalysisFinish();
    if (!isActive) {
      return;
    }
    update(() {
      error = failure;
      onDrafts(drafts);
      analyzing = false;
    });
  }

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
