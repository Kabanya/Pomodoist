import 'dart:typed_data';

/// A device-local recording. Account ownership prevents cross-account retries.
class VoiceRecording {
  const VoiceRecording({
    required this.path,
    required this.ownerId,
    this.locale,
  });
  final String path;
  final String ownerId;
  final String? locale;
}

const voicePcmSampleRate = 16000;

abstract interface class VoiceMicrophone {
  Stream<double> get amplitudeDbfs;
  Future<bool> hasPermission({bool request = true});
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

abstract interface class VoiceRecorder implements VoiceMicrophone {
  Future<void> start(String path);
}

abstract interface class PcmVoiceRecorder implements VoiceMicrophone {
  Future<Stream<Uint8List>> startPcm();
}

abstract interface class VoiceRecordingStore {
  Future<String> createPath();
  Future<VoiceRecording?> load();
  Future<void> save(VoiceRecording recording);
  Future<Uint8List> read(VoiceRecording recording);
  Future<void> remove(VoiceRecording recording);
}
