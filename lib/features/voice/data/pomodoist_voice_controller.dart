import 'package:app_voice/app_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'backend_voice_recognizer.dart';
import 'record_voice_recorder.dart';
import 'voice_recording_store.dart';

bool usesBackendVoice({required bool isWeb, required TargetPlatform platform}) =>
    isWeb || (platform != TargetPlatform.iOS && platform != TargetPlatform.macOS);

VoiceRecognitionController createPomodoistVoiceController({
  required VoiceBackendInvoke invoke,
  required String? Function() ownerId,
}) {
  if (!usesBackendVoice(isWeb: kIsWeb, platform: defaultTargetPlatform)) {
    return VoiceRecognitionController(); // Preserve Apple's implementation.
  }
  return BackendVoiceController(BackendVoiceRecognizer(
    recorder: RecordVoiceRecorder(),
    store: createVoiceRecordingStore(),
    ownerId: ownerId,
    invoke: invoke,
  ));
}

/// Remote transcription needs microphone permission, not Apple Speech access.
class BackendVoiceController extends VoiceRecognitionController {
  BackendVoiceController(this.recognizer) : super(
    recordedRecognizer: recognizer,
    platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
  );
  final BackendVoiceRecognizer recognizer;

  @override
  Future<Map<String, Object?>> checkAccess({String? locale, bool request = false}) async {
    final granted = await recognizer.hasPermission(request: request);
    return {
      'microphone': granted ? 'authorized' : (request ? 'denied' : 'notDetermined'),
      'speech': 'authorized',
    };
  }

  @override
  Future<bool> openSettings(VoiceSettingsDestination destination) async {
    if (kIsWeb) return recognizer.hasPermission(request: true);
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await const MethodChannel('pomodoist/voice_settings')
          .invokeMethod<bool>('openMicrophoneSettings') ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return launchUrl(Uri.parse('ms-settings:privacy-microphone'));
    }
    return false;
  }
}
