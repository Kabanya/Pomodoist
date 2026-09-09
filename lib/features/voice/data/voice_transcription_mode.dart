import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const voiceTranscriptionModePreferenceKey = 'voice.transcriptionMode';

enum VoiceTranscriptionMode {
  system('system'),
  cloud('cloud');

  const VoiceTranscriptionMode(this.storageValue);

  final String storageValue;

  static VoiceTranscriptionMode fromStorageValue(Object? value) =>
      value == VoiceTranscriptionMode.cloud.storageValue
      ? VoiceTranscriptionMode.cloud
      : VoiceTranscriptionMode.system;
}

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

const _appleSpeechFallbackErrors = {
  'speech_authorization_denied',
  'speech_permission_denied',
  'speech_authorization_restricted',
  'speech_dictation_disabled',
  'speech_unavailable',
  'speech_recognition_failed',
  'speech_locale_unsupported',
  'speech_network_unavailable',
};

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
    _appleSpeechFallbackErrors.contains(errorCode);

final voiceTranscriptionModeProvider =
    NotifierProvider<VoiceTranscriptionModeController, VoiceTranscriptionMode>(
      VoiceTranscriptionModeController.new,
    );

class VoiceTranscriptionModeController
    extends Notifier<VoiceTranscriptionMode> {
  bool _loaded = false;
  bool _hasLocalSelection = false;
  Future<void>? _loading;

  Future<void> get ready => _loading ?? Future<void>.value();

  @override
  VoiceTranscriptionMode build() {
    if (!_loaded) {
      _loaded = true;
      final loading = _load();
      _loading = loading;
      unawaited(
        loading.whenComplete(() {
          if (identical(_loading, loading)) _loading = null;
        }),
      );
    }
    return VoiceTranscriptionMode.system;
  }

  Future<void> setMode(VoiceTranscriptionMode mode) async {
    _hasLocalSelection = true;
    state = mode;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        voiceTranscriptionModePreferenceKey,
        mode.storageValue,
      );
    } on MissingPluginException {
      // Tests and unsupported embeddings may not provide persistent storage.
    }
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = VoiceTranscriptionMode.fromStorageValue(
        preferences.get(voiceTranscriptionModePreferenceKey),
      );
      if (ref.mounted && !_hasLocalSelection) state = stored;
    } on MissingPluginException {
      // Keep the safe system default when persistent storage is unavailable.
    }
  }
}
