import 'dart:async';

import 'package:app_voice/app_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/voice/captured_voice_repository.dart';
import 'package:pomodoist/data/services/voice/voice_capture_service.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

void main() {
  test('capture repository ignores late events and releases once', () async {
    final voice = _Voice();
    final repository = _repository(voice);
    final received = <VoiceCaptureState>[];
    final done = Completer<void>();
    final subscription = repository.watchState().listen(
      received.add,
      onDone: done.complete,
    );
    await Future<void>.delayed(Duration.zero);
    (await repository.restore()).getOrThrow();
    (await repository.start('en')).getOrThrow();
    voice.events.add(VoiceRecognitionEvent.recording);
    await Future<void>.delayed(Duration.zero);
    expect(repository.currentState.isCapturing, isTrue);
    final published = received.length;

    repository.dispose();
    repository.dispose();
    expect(voice.cancels, 1);
    expect(voice.aborts, 0);
    voice.events.add(VoiceRecognitionEvent.completed(text: 'Late'));
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(published));
    expect(repository.currentState.transcript, isEmpty);
    await subscription.cancel();
    await done.future;
  });

  test('disposal during transcription aborts instead of cancelling', () async {
    final voice = _Voice();
    final repository = _repository(voice);
    (await repository.restore()).getOrThrow();
    (await repository.start('en')).getOrThrow();
    voice.events.add(VoiceRecognitionEvent.transcribing);
    await Future<void>.delayed(Duration.zero);
    expect(repository.currentState.isTranscribing, isTrue);

    repository.dispose();
    expect(voice.aborts, 1);
    expect(voice.cancels, 0);
  });
}

CapturedVoiceRepository _repository(_Voice voice) => CapturedVoiceRepository(
  initialController: AppVoiceCaptureService(voice),
  waitForMode: () async {},
  effectiveMode: () => VoiceTranscriptionMode.cloud,
  replaceController: () => AppVoiceCaptureService(voice),
  setMode: (_) async {},
  signedIn: () => true,
);

class _Voice implements VoiceRecognitionController {
  final events = StreamController<VoiceRecognitionEvent>.broadcast();
  int cancels = 0;
  int aborts = 0;

  @override
  bool get canRetryTranscription => false;
  @override
  Stream<double> get amplitudeDbfs => const Stream.empty();
  @override
  Stream<VoiceRecognitionEvent> start(VoiceRecognitionConfig config) =>
      events.stream;
  @override
  Stream<VoiceRecognitionEvent> retryTranscription() => events.stream;
  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> abortTranscription() async {
    aborts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
