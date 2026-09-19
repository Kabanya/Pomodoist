import 'package:flutter/foundation.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

bool supportsVoiceTranscriptionModeSelection({
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    !isWeb &&
    (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS);

VoiceTranscriptionMode effectiveVoiceTranscriptionMode({
  required bool isWeb,
  required TargetPlatform platform,
  required VoiceTranscriptionMode preferred,
  required bool signedIn,
}) {
  if (!supportsVoiceTranscriptionModeSelection(
    isWeb: isWeb,
    platform: platform,
  )) {
    return VoiceTranscriptionMode.cloud;
  }
  return preferred == VoiceTranscriptionMode.cloud && !signedIn
      ? VoiceTranscriptionMode.system
      : preferred;
}

bool canOfferCloudTranscriptionFallback({
  required bool isWeb,
  required TargetPlatform platform,
  required VoiceTranscriptionMode mode,
  required bool signedIn,
  required String? errorCode,
}) =>
    supportsVoiceTranscriptionModeSelection(isWeb: isWeb, platform: platform) &&
    mode == VoiceTranscriptionMode.system &&
    signedIn &&
    const {
      'speech_authorization_denied',
      'speech_permission_denied',
      'speech_authorization_restricted',
      'speech_dictation_disabled',
      'speech_unavailable',
      'speech_recognition_failed',
      'speech_locale_unsupported',
      'speech_network_unavailable',
    }.contains(errorCode);
