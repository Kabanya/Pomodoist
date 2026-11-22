import 'dart:async';
import 'dart:typed_data';

import 'package:app_voice/app_voice.dart';

import 'package:pomodoist/data/services/voice/voice_recording.dart';

/// Buffers local dictation in memory and releases it after processing.
class LocalVoiceRecognizer extends RecordedVoiceRecognizer
    implements RecordedVoiceAmplitudeSource {
  LocalVoiceRecognizer({
    required PcmVoiceRecorder recorder,
    required this.transcribe,
    this.onStart,
  }) : _recorder = recorder;

  final void Function()? onStart;
  final PcmVoiceRecorder _recorder;
  final Future<String> Function(Uint8List, String?, Future<void>) transcribe;
  _PcmCapture? _capture;
  Completer<void>? _cancellation;

  @override
  Stream<double> get amplitudeDbfs => _recorder.amplitudeDbfs;

  Future<bool> hasPermission({bool request = false}) =>
      _recorder.hasPermission(request: request);

  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    onStart?.call();
    if (!await hasPermission(request: true)) throw _microphoneDenied;
    try {
      final stream = await _recorder.startPcm();
      _capture = _PcmCapture(
        stream,
        config.maxDuration.inSeconds * voicePcmSampleRate * 2,
      );
    } catch (_) {
      throw _microphoneDenied;
    }
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) async {
    final capture = _capture;
    if (capture == null) throw _emptyRecording;
    _capture = null;
    final cancellation = _cancellation = Completer<void>();
    try {
      await _recorder.stop();
      if (cancellation.isCompleted) throw _canceled;
      if (capture.failed) throw _microphoneDenied;
      final pcm = capture.takeBytes();
      if (pcm.isEmpty) throw _emptyRecording;
      final text = (await Future.any([
        transcribe(pcm, config.locale, cancellation.future),
        cancellation.future.then<String>((_) => throw _canceled),
      ])).trim();
      if (text.isEmpty) {
        throw const VoiceRecognitionException(
          'empty_transcript',
          'No speech recognized.',
        );
      }
      return VoiceRecognitionTranscript(text: text);
    } on VoiceRecognitionException {
      rethrow;
    } catch (_) {
      throw const VoiceRecognitionException(
        'speech_recognition_failed',
        'Local speech recognition failed.',
      );
    } finally {
      if (!cancellation.isCompleted) cancellation.complete();
      if (identical(_cancellation, cancellation)) _cancellation = null;
      await capture.close();
    }
  }

  @override
  Future<void> abortTranscription() => cancel();

  @override
  Future<void> cancel() async {
    final cancellation = _cancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    final capture = _capture;
    if (capture == null) return;
    _capture = null;
    try {
      await _recorder.cancel();
    } finally {
      await capture.close();
    }
  }

  @override
  void dispose() {
    unawaited(_recorder.dispose().catchError((Object _) {}));
  }

  static const _microphoneDenied = VoiceRecognitionException(
    'microphone_denied',
    'The microphone could not be opened.',
  );
  static const _emptyRecording = VoiceRecognitionException(
    'empty_recording',
    'No audio was recorded.',
  );
  static const _canceled = VoiceRecognitionException(
    'speech_canceled',
    'Local recognition was canceled.',
  );
}

class _PcmCapture {
  _PcmCapture(Stream<Uint8List> stream, int maximumBytes) {
    _subscription = stream.listen((bytes) {
      final remaining = maximumBytes - _audio.length;
      if (remaining <= 0) return;
      _audio.add(
        bytes.length <= remaining
            ? bytes
            : Uint8List.sublistView(bytes, 0, remaining),
      );
    }, onError: (Object _) => failed = true);
  }
  final _audio = BytesBuilder(copy: false);
  late final StreamSubscription<Uint8List> _subscription;
  bool failed = false;

  Uint8List takeBytes() => _audio.takeBytes();

  Future<void> close() async {
    await _subscription.cancel();
    _audio.clear();
  }
}
