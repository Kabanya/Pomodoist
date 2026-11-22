import 'package:pomodoist/domain/models/voice/whisper_model.dart';
import 'package:app_voice/app_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pomodoist/data/services/voice/android_system_voice_controller.dart';
import 'package:pomodoist/data/services/voice/backend_voice_recognizer.dart';
import 'package:pomodoist/data/services/voice/local_voice_engine.dart';
import 'package:pomodoist/data/services/voice/local_voice_recognizer.dart';
import 'package:pomodoist/data/services/voice/voice_transcription_policy.dart';
import 'package:pomodoist/data/services/voice/record_voice_recorder.dart';
import 'package:pomodoist/data/services/voice/voice_recording_store.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

bool usesBackendVoice({
  required bool isWeb,
  required TargetPlatform platform,
  required VoiceTranscriptionMode mode,
}) =>
    !supportsVoiceTranscriptionModeSelection(
      isWeb: isWeb,
      platform: platform,
    ) ||
    mode == VoiceTranscriptionMode.cloud;

VoiceRecognitionController createPomodoistVoiceController({
  required VoiceBackendInvoke invoke,
  required String? Function() ownerId,
  required VoiceTranscriptionMode mode,
  WhisperModel Function()? selectedModel,
}) {
  if (!usesBackendVoice(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    mode: mode,
  )) {
    if (usesDownloadableVoiceModel(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      late WhisperModel recordingModel;
      final recognizer = LocalVoiceRecognizer(
        recorder: RecordVoiceRecorder(),
        onStart: () =>
            recordingModel = selectedModel?.call() ?? WhisperModel.tiny,
        transcribe: (pcm, locale, cancellation) =>
            transcribeLocally(pcm, locale, cancellation, tier: recordingModel),
      );
      return _MicrophoneVoiceController(recognizer, recognizer.hasPermission);
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? AndroidSystemVoiceController()
        : VoiceRecognitionController();
  }
  return BackendVoiceController(
    BackendVoiceRecognizer(
      recorder: RecordVoiceRecorder(),
      store: createVoiceRecordingStore(),
      ownerId: ownerId,
      invoke: invoke,
    ),
  );
}

/// Remote transcription needs microphone permission, not Apple Speech access.
class BackendVoiceController extends _MicrophoneVoiceController {
  BackendVoiceController(BackendVoiceRecognizer recognizer)
    : super(recognizer, recognizer.hasPermission);
}

class _MicrophoneVoiceController extends VoiceRecognitionController {
  _MicrophoneVoiceController(
    RecordedVoiceRecognizer recognizer,
    this._hasPermission,
  ) : super(
        recordedRecognizer: recognizer,
        platformSupport: const VoicePlatformSupport(
          supportsRecordedSystem: true,
        ),
      );
  final Future<bool> Function({bool request}) _hasPermission;

  @override
  Future<Map<String, Object?>> checkAccess({
    String? locale,
    bool request = false,
  }) async {
    final granted = await _hasPermission(request: request);
    return {
      'microphone': granted
          ? 'authorized'
          : (request ? 'denied' : 'notDetermined'),
      'speech': 'authorized',
    };
  }

  @override
  Future<bool> openSettings(VoiceSettingsDestination destination) async {
    if (kIsWeb) return _hasPermission(request: true);
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await const MethodChannel(
            'pomodoist/voice_settings',
          ).invokeMethod<bool>('openMicrophoneSettings') ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return launchUrl(Uri.parse('ms-settings:privacy-microphone'));
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        destination == VoiceSettingsDestination.microphone) {
      return MethodChannelSystemSpeechTranscriber().openSettings(destination);
    }
    return false;
  }
}
