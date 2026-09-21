import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:pomodoist/data/repositories/voice/voice_capture_repository.dart';
import 'package:pomodoist/data/services/voice/pomodoist_voice_controller.dart';
import 'package:pomodoist/data/services/voice/voice_capture_service.dart';
import 'package:pomodoist/data/services/voice/voice_transcription_policy.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/utils/result.dart';

/// Owns the recorder handle and transcription stream for one voice session.
///
/// Composition supplies mode policy callbacks and a signed-in lookup; the
/// repository itself reads no providers, preferences or UI controllers. The
/// locale arrives with each operation instead of living in mutable state.
final class CapturedVoiceRepository implements VoiceCaptureRepository {
  CapturedVoiceRepository({
    required VoiceCaptureService initialController,
    required Future<void> Function() waitForMode,
    required VoiceTranscriptionMode Function() effectiveMode,
    required VoiceCaptureService Function() replaceController,
    required Future<void> Function(VoiceTranscriptionMode) setMode,
    required bool Function() signedIn,
  }) : _waitForMode = waitForMode,
       _effectiveMode = effectiveMode,
       _replaceController = replaceController,
       _setMode = setMode,
       _signedIn = signedIn,
       _voiceController = initialController {
    _voiceMode =
        supportsVoiceTranscriptionModeSelection(
              isWeb: kIsWeb,
              platform: defaultTargetPlatform,
            ) &&
            initialController is! BackendVoiceController
        ? VoiceTranscriptionMode.system
        : VoiceTranscriptionMode.cloud;
  }

  final Future<void> Function() _waitForMode;
  final VoiceTranscriptionMode Function() _effectiveMode;
  final VoiceCaptureService Function() _replaceController;
  final Future<void> Function(VoiceTranscriptionMode) _setMode;
  final bool Function() _signedIn;

  final _states = StreamController<VoiceCaptureState>.broadcast();
  VoiceCaptureService _voiceController;
  late VoiceTranscriptionMode _voiceMode;
  VoiceCaptureStatus _status = VoiceCaptureStatus.idle;
  StreamSubscription<VoiceCaptureEvent>? _subscription;
  StreamSubscription<double>? _amplitudeSubscription;
  String _locale = 'en';
  String _transcript = '';
  VoiceCaptureFailure? _failure;
  String _recognitionErrorMessage = '';
  String? _voiceErrorCode;
  Map<String, Object?> _access = const {};
  bool _accessBusy = false;
  bool _restoring = true;
  int _accessCheck = 0;
  bool _stopping = false;
  bool _captureActive = false;
  double _amplitudeLevel = 0;
  int _recordingSecondsRemaining = voiceQuickAddMaxDuration.inSeconds;
  Timer? _recordingTimer;
  bool _disposed = false;

  bool get _isActive => !_disposed;

  bool get _isCapturing =>
      _status == VoiceCaptureStatus.recording ||
      _status == VoiceCaptureStatus.requestingPermission;

  bool get _isTranscribing => _status == VoiceCaptureStatus.transcribing;

  bool get _canStart =>
      !_restoring &&
      !_accessBusy &&
      !_captureActive &&
      !_isCapturing &&
      !_isTranscribing;

  @override
  VoiceCaptureState get currentState => VoiceCaptureState(
    status: _status,
    transcript: _transcript,
    failure: _failure,
    recognitionErrorMessage: _recognitionErrorMessage,
    voiceErrorCode: _voiceErrorCode,
    restoring: _restoring,
    accessBusy: _accessBusy,
    stopping: _stopping,
    capturing: _captureActive,
    amplitudeLevel: _amplitudeLevel,
    recordingSecondsRemaining: _recordingSecondsRemaining,
    canRetryTranscription: _voiceController.canRetryTranscription,
    canUseCloudFallback: _canUseCloudFallback,
    needsPermissionRequest: _needsPermissionRequest,
    settingsDestination: _settingsDestination,
    cloudMode: _voiceMode == VoiceTranscriptionMode.cloud,
  );

  @override
  Stream<VoiceCaptureState> watchState() {
    final controller = StreamController<VoiceCaptureState>();
    controller.add(currentState);
    final subscription = _states.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
    return controller.stream;
  }

  void _emit() {
    if (_disposed) return;
    _states.add(currentState);
  }

  void _update(void Function() action) {
    if (_disposed) return;
    action();
    _emit();
  }

  bool get _accessRestricted =>
      _access['microphone'] == 'restricted' ||
      _access['speech'] == 'restricted' ||
      (_access.isEmpty &&
          (_voiceErrorCode == 'microphone_restricted' ||
              _voiceErrorCode == 'speech_authorization_restricted'));

  bool get _canUseCloudFallback =>
      _access['microphone'] != 'denied' &&
      _access['microphone'] != 'restricted' &&
      canOfferCloudTranscriptionFallback(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
        mode: _voiceMode,
        signedIn: _signedIn(),
        errorCode: _voiceErrorCode,
      );

  bool get _needsPermissionRequest =>
      !_accessRestricted &&
      (_access['microphone'] == 'notDetermined' ||
          _access['speech'] == 'notDetermined');

  VoiceAccessSettings? get _settingsDestination {
    if (_accessRestricted) return null;
    if (_access['microphone'] == 'denied' ||
        _voiceErrorCode == 'microphone_denied') {
      return VoiceAccessSettings.microphone;
    }
    if (_voiceMode != VoiceTranscriptionMode.system) return null;
    if (_access['speech'] == 'denied' ||
        _voiceErrorCode == 'speech_authorization_denied' ||
        _voiceErrorCode == 'speech_permission_denied') {
      return VoiceAccessSettings.speech;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        (_voiceErrorCode == 'speech_dictation_disabled' ||
            _voiceErrorCode == 'speech_unavailable' ||
            _voiceErrorCode == 'speech_recognition_failed')) {
      return VoiceAccessSettings.dictation;
    }
    return null;
  }

  @override
  Future<Result<void>> start(String locale, {bool retry = false}) =>
      Result.capture(() => _start(locale, retry: retry));

  @override
  Future<Result<void>> stop() => Result.capture(_stop);

  @override
  Future<Result<bool>> close() => Result.capture(_close);

  @override
  Future<Result<void>> restore() => Result.capture(_restore);

  @override
  Future<Result<void>> refreshAccess({
    required String locale,
    bool request = false,
  }) => Result.capture(() {
    _locale = locale;
    return _refreshAccess(request: request);
  });

  @override
  Future<Result<void>> recoverAccess(String locale) => Result.capture(() {
    _locale = locale;
    return _recoverAccess();
  });

  @override
  Future<Result<void>> useCloudTranscription(String locale) =>
      Result.capture(() {
        _locale = locale;
        return _useCloudTranscription();
      });

  Future<void> _start(String locale, {bool retry = false}) async {
    if (!_canStart) return;
    _locale = locale;
    if (!retry) {
      _update(() => _accessBusy = true);
      try {
        await _syncVoiceControllerForNewRecording();
      } catch (_) {
        if (_isActive) {
          _update(() => _failure = VoiceCaptureFailure.general);
        }
        return;
      } finally {
        if (_isActive) _update(() => _accessBusy = false);
      }
      if (!_isActive || !_canStart) return;
    }
    _update(() {
      _captureActive = true;
      _status = retry
          ? VoiceCaptureStatus.transcribing
          : VoiceCaptureStatus.requestingPermission;
      _failure = null;
      _voiceErrorCode = null;
      _access = const {};
      ++_accessCheck;
      _transcript = '';
    });
    _stopRecordingCountdown();
    _stopAmplitudeMeter();
    final previousSubscription = _subscription;
    _subscription = null;
    await previousSubscription?.cancel();
    if (!_isActive) return;
    try {
      final stream = retry
          ? _voiceController.retryTranscription()
          : _voiceController.start(
              VoiceCaptureConfig(
                locale: locale,
                maxDuration: voiceQuickAddMaxDuration,
              ),
            );
      _subscription = stream.listen(
        _handleEvent,
        onDone: () {
          if (!_isActive) return;
          _stopRecordingCountdown();
          _stopAmplitudeMeter();
          _update(() {
            _captureActive = false;
            if (_isCapturing || _isTranscribing) {
              _status = VoiceCaptureStatus.idle;
            }
          });
        },
      );
    } catch (error) {
      _update(() {
        _captureActive = false;
        _status = VoiceCaptureStatus.error;
        _voiceErrorCode = error is VoiceCaptureException ? error.code : null;
        _recognitionErrorMessage = error.toString();
        _failure = VoiceCaptureFailure.recognition;
      });
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    _update(() => _stopping = true);
    try {
      await _voiceController.stop();
    } catch (_) {
      if (_isActive) _update(() => _failure = VoiceCaptureFailure.general);
    } finally {
      if (_isActive) _update(() => _stopping = false);
    }
  }

  Future<bool> _close() async {
    _update(() {
      _captureActive = false;
      _status = VoiceCaptureStatus.canceled;
    });
    try {
      await _voiceController.cancel();
      return _isActive;
    } catch (_) {
      if (_isActive) _update(() => _failure = VoiceCaptureFailure.general);
    }
    return false;
  }

  Future<void> _restore() async {
    try {
      await _waitForMode();
      if (!_isActive) return;
      final mode = _effectiveMode();
      if (mode != _voiceMode) {
        // Select the saved mode before restoring; opening must not discard audio.
        _replaceVoiceController(mode);
      }
      await _voiceController.restorePendingRecording();
    } catch (_) {
      if (_isActive) _failure = VoiceCaptureFailure.general;
    }
    if (!_isActive) return;
    _update(() => _restoring = false);
    if (_voiceController.canRetryTranscription) await _refreshAccess();
  }

  void _handleEvent(VoiceCaptureEvent event) {
    if (!_isActive) return;
    // Recording side effects run before the state is emitted so the snapshot
    // carries the reset countdown instead of the previous recording's value.
    if (event.status == VoiceCaptureStatus.recording) {
      _startRecordingCountdown();
      _startAmplitudeMeter();
    } else if (event.status == VoiceCaptureStatus.transcribing ||
        event.status == VoiceCaptureStatus.completed ||
        event.status == VoiceCaptureStatus.canceled ||
        event.status == VoiceCaptureStatus.error ||
        event.status == VoiceCaptureStatus.unsupportedPlatform) {
      _stopRecordingCountdown();
      _stopAmplitudeMeter();
    }
    _update(() {
      _status = event.status;
      switch (event.status) {
        case VoiceCaptureStatus.completed:
          _captureActive = false;
          _transcript = event.finalText ?? _transcript;
        case VoiceCaptureStatus.canceled:
          _captureActive = false;
        case VoiceCaptureStatus.error:
        case VoiceCaptureStatus.unsupportedPlatform:
          _captureActive = false;
          _voiceErrorCode = event.error?.code;
          _recognitionErrorMessage = event.error?.message ?? "";
          _failure = event.error == null
              ? null
              : VoiceCaptureFailure.recognition;
        case VoiceCaptureStatus.idle:
        case VoiceCaptureStatus.requestingPermission:
        case VoiceCaptureStatus.recording:
        case VoiceCaptureStatus.transcribing:
          break;
      }
    });
    if (event.status == VoiceCaptureStatus.error) {
      unawaited(_refreshAccess());
    }
  }

  Future<void> _syncVoiceControllerForNewRecording() async {
    await _waitForMode();
    final mode = _effectiveMode();
    if (mode == _voiceMode) return;
    await _voiceController.cancel();
    if (!_isActive) return;
    _replaceVoiceController(mode);
  }

  void _replaceVoiceController(VoiceTranscriptionMode mode) {
    _voiceController = _replaceController();
    _voiceMode = mode;
  }

  Future<void> _useCloudTranscription() async {
    if (!_canStart || !_canUseCloudFallback) return;
    _update(() => _accessBusy = true);
    try {
      await _voiceController.cancel();
      await _setMode(VoiceTranscriptionMode.cloud);
      if (!_isActive) return;
      _replaceVoiceController(VoiceTranscriptionMode.cloud);
      _update(() {
        _failure = null;
        _voiceErrorCode = null;
      });
    } catch (_) {
      if (_isActive) {
        _update(() => _failure = VoiceCaptureFailure.general);
      }
      return;
    } finally {
      if (_isActive) _update(() => _accessBusy = false);
    }
    if (_isActive) await _start(_locale);
  }

  Future<void> _refreshAccess({bool request = false}) async {
    final check = ++_accessCheck;
    try {
      final access = await _voiceController.checkAccess(
        locale: _locale,
        request: request,
      );
      if (!_isActive || check != _accessCheck) return;
      _update(() {
        _access = access;
        if (access['microphone'] == 'restricted' ||
            access['speech'] == 'restricted') {
          _voiceErrorCode = access['microphone'] == 'restricted'
              ? 'microphone_restricted'
              : 'speech_authorization_restricted';
          _failure = VoiceCaptureFailure.restricted;
        } else if (access['microphone'] == 'denied') {
          _voiceErrorCode = 'microphone_denied';
          _failure = VoiceCaptureFailure.microphoneDenied;
        } else if (access['speech'] == 'denied') {
          _voiceErrorCode = 'speech_authorization_denied';
          _failure = VoiceCaptureFailure.speechDenied;
        } else if (access['microphone'] == 'authorized' &&
            access['speech'] == 'authorized' &&
            const [
              'microphone_denied',
              'microphone_restricted',
              'speech_authorization_restricted',
              'speech_permission_denied',
              'speech_authorization_denied',
            ].contains(_voiceErrorCode)) {
          _voiceErrorCode = null;
          _failure = null;
        }
      });
    } on MissingPluginException {
      // Platforms without Apple Speech have no permission recovery channel.
    } catch (_) {
      // Preserve the actionable recognition error if the status service also fails.
    }
  }

  Future<void> _recoverAccess() async {
    final destination = _settingsDestination;
    final request = _needsPermissionRequest;
    _update(() => _accessBusy = true);
    try {
      if (request) {
        await _refreshAccess(request: true);
      } else if (destination != null) {
        final opened = await _voiceController.openSettings(destination);
        if (!opened && _isActive) {
          _update(() => _failure = VoiceCaptureFailure.settings);
        }
      }
    } catch (_) {
      if (_isActive) _update(() => _failure = VoiceCaptureFailure.settings);
    } finally {
      if (_isActive) _update(() => _accessBusy = false);
    }
  }

  void _startRecordingCountdown() {
    _recordingTimer?.cancel();
    _recordingSecondsRemaining = voiceQuickAddMaxDuration.inSeconds;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isActive || _status != VoiceCaptureStatus.recording) {
        timer.cancel();
        return;
      }
      _update(() {
        if (_recordingSecondsRemaining > 0) {
          _recordingSecondsRemaining -= 1;
        }
      });
      if (_recordingSecondsRemaining == 0) {
        timer.cancel();
      }
    });
  }

  void _stopRecordingCountdown() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  void _startAmplitudeMeter() {
    final previous = _amplitudeSubscription;
    if (previous != null) {
      unawaited(previous.cancel());
    }
    _amplitudeSubscription = _voiceController.amplitudeDbfs.listen((dbfs) {
      if (!_isActive ||
          _status != VoiceCaptureStatus.recording ||
          !dbfs.isFinite) {
        return;
      }
      _update(() {
        _amplitudeLevel = ((dbfs + 60) / 60).clamp(0.0, 1.0);
      });
    }, onError: (_) {});
  }

  void _stopAmplitudeMeter() {
    final subscription = _amplitudeSubscription;
    _amplitudeSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (_amplitudeLevel != 0) {
      _update(() => _amplitudeLevel = 0);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _subscription?.cancel();
    _amplitudeSubscription?.cancel();
    _recordingTimer?.cancel();
    if (_stopping || _isTranscribing) {
      unawaited(_voiceController.abortTranscription());
    } else if (_captureActive || _isCapturing) {
      unawaited(_voiceController.cancel());
    }
    unawaited(_states.close());
  }
}
