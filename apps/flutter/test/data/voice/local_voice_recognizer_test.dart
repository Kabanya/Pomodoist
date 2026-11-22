import 'dart:async';
import 'dart:typed_data';

import 'package:app_voice/app_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/voice/local_voice_audio.dart';
import 'package:pomodoist/data/services/voice/local_voice_recognizer.dart';
import 'package:pomodoist/data/services/voice/voice_recording.dart';

import '../../../testing/fakes/fake_voice_recorder.dart';

void main() {
  const config = VoiceRecognitionConfig(locale: 'ru-RU');
  late _PcmRecorder recorder;
  setUp(() => recorder = _PcmRecorder());

  test('hands microphone PCM to the local decoder in capture order', () async {
    final recognizer = LocalVoiceRecognizer(
      recorder: recorder,
      transcribe: (pcm, locale, _) async {
        expect(pcm, [1, 0, 2, 0]);
        expect(locale, 'ru-RU');
        return '  Купить продукты  ';
      },
    );
    await recognizer.start(config);
    recorder.stream.add(Uint8List.fromList([1, 0]));
    recorder.stream.add(Uint8List.fromList([2, 0]));

    expect((await recognizer.stop(config)).text, 'Купить продукты');
    expect(recognizer.canRetryTranscription, isFalse);
    expect(await recognizer.restorePendingRecording(), isFalse);
  });

  test('abort releases processing and discards a late result', () async {
    final started = Completer<void>();
    final finish = Completer<String>();
    final recognizer = LocalVoiceRecognizer(
      recorder: recorder,
      transcribe: (pcm, locale, cancellation) {
        started.complete();
        return finish.future;
      },
    );
    await recognizer.start(config);
    recorder.stream.add(Uint8List.fromList([1, 0]));
    final result = recognizer.stop(config);
    await started.future;
    final canceled = expectLater(result, throwsA(_code('speech_canceled')));
    await recognizer.abortTranscription();
    await canceled;
    finish.complete('Late result');
    expect(recognizer.canRetryTranscription, isFalse);
  });

  test('recognizes silence without loading the speech model', () {
    expect(localVoiceSegments(Uint8List(32000), 16000), isEmpty);
  });

  test('preserves speech order and keeps long inputs within model windows', () {
    const rate = 16000;
    final bytes = ByteData(rate * 54 * 2);
    for (var i = 0; i < rate * 54; i++) {
      final value = i < rate * 48 ? 4096 : -4096;
      bytes.setInt16(i * 2, value, Endian.little);
    }
    final segments = localVoiceSegments(bytes.buffer.asUint8List(), rate);
    expect(segments, hasLength(3));
    expect(segments.every((part) => part.length <= rate * 25), isTrue);
    expect(
      segments.fold<int>(0, (total, part) => total + part.length),
      rate * 54,
    );
    expect(segments.first.first, .125);
    expect(segments.last.last, -.125);
  });
}

Matcher _code(String code) => isA<VoiceRecognitionException>().having(
  (error) => error.code,
  'code',
  code,
);

class _PcmRecorder extends FakeVoiceRecorder implements PcmVoiceRecorder {
  final stream = StreamController<Uint8List>();

  @override
  Future<Stream<Uint8List>> startPcm() async => stream.stream;

  @override
  Future<String?> stop() async {
    await stream.close();
    return null;
  }
}
