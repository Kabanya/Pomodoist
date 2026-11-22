import 'dart:typed_data';

import 'package:record/record.dart';

import 'package:pomodoist/data/services/voice/voice_recording.dart';

class RecordVoiceRecorder implements VoiceRecorder, PcmVoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Stream<double> get amplitudeDbfs => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((amplitude) => amplitude.current);
  @override
  Future<bool> hasPermission({bool request = true}) =>
      _recorder.hasPermission(request: request);
  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: voicePcmSampleRate,
      numChannels: 1,
    ),
    path: path,
  );
  @override
  Future<Stream<Uint8List>> startPcm() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: voicePcmSampleRate,
      numChannels: 1,
    ),
  );
  @override
  Future<String?> stop() => _recorder.stop();
  @override
  Future<void> cancel() => _recorder.cancel();
  @override
  Future<void> dispose() => _recorder.dispose();
}
