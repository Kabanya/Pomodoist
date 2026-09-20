import 'package:pomodoist/data/services/voice/voice_capture_service.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'dart:async';

import 'package:app_voice/app_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/voice/captured_voice_repository.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restore waits for saved mode and replaces without discarding audio',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ready = Completer<void>();
      final original = _Voice();
      final replacement = _Voice();
      var replacements = 0;
      final repository = _repository(
        original,
        waitForMode: () => ready.future,
        replace: () {
          replacements++;
          return replacement;
        },
      );
      addTearDown(repository.dispose);
      final restored = repository.restore();
      expect(repository.currentState.canStart, isFalse);
      expect(replacements, 0);
      ready.complete();
      (await restored).getOrThrow();
      expect(replacements, 1);
      expect(original.cancels, 0);
      expect(replacement.restores, 1);
      expect(repository.currentState.canStart, isTrue);
      expect(repository.currentState.restoring, isFalse);
    },
  );

  test(
    'stop is single-flight and disposal aborts while explicit close discards',
    () async {
      final voice = _Voice();
      final stopped = Completer<void>();
      voice.stopped = stopped.future;
      final repository = _repository(voice);
      addTearDown(repository.dispose);
      (await repository.restore()).getOrThrow();
      (await repository.start('en')).getOrThrow();
      voice.events.add(VoiceRecognitionEvent.recording);
      await Future<void>.delayed(Duration.zero);
      expect(repository.currentState.isCapturing, isTrue);
      final first = repository.stop();
      await repository.stop();
      expect(voice.stops, 1);
      repository.dispose();
      expect(voice.aborts, 1);
      expect(voice.cancels, 0);
      stopped.complete();
      await first.then((result) => result.getOrThrow());

      final discarded = _Voice();
      final closing = _repository(discarded);
      addTearDown(closing.dispose);
      (await closing.restore()).getOrThrow();
      (await closing.start('en')).getOrThrow();
      discarded.events.add(VoiceRecognitionEvent.transcribing);
      await Future<void>.delayed(Duration.zero);
      expect((await closing.close()).getOrThrow(), isTrue);
      expect(closing.currentState.status, VoiceCaptureStatus.canceled);
      closing.dispose();
      expect(discarded.cancels, 1);
      expect(discarded.aborts, 0);
    },
  );

  test('denied microphone access exposes the settings target', () async {
    final voice = _Voice()
      ..access = {'microphone': 'denied', 'speech': 'authorized'};
    final repository = _repository(voice);
    addTearDown(repository.dispose);
    (await repository.refreshAccess(locale: 'en', request: true)).getOrThrow();
    expect(repository.currentState.voiceErrorCode, 'microphone_denied');
    expect(
      repository.currentState.settingsDestination,
      VoiceAccessSettings.microphone,
    );
    expect(repository.currentState.needsPermissionRequest, isFalse);
    expect(repository.currentState.canUseCloudFallback, isFalse);
  });
}

CapturedVoiceRepository _repository(
  _Voice voice, {
  Future<void> Function()? waitForMode,
  VoiceRecognitionController Function()? replace,
}) => CapturedVoiceRepository(
  initialController: AppVoiceCaptureService(voice),
  waitForMode: waitForMode ?? () async {},
  effectiveMode: () => VoiceTranscriptionMode.cloud,
  replaceController: () => AppVoiceCaptureService((replace ?? () => voice)()),
  setMode: (_) async {},
  signedIn: () => true,
);

class _Voice implements VoiceRecognitionController {
  final events = StreamController<VoiceRecognitionEvent>.broadcast();
  int starts = 0;
  int retries = 0;
  int cancels = 0;
  int aborts = 0;
  int stops = 0;
  int restores = 0;
  Future<void>? stopped;
  Map<String, Object?> access = {
    'microphone': 'authorized',
    'speech': 'authorized',
  };

  @override
  bool get canRetryTranscription => false;
  @override
  Stream<double> get amplitudeDbfs => const Stream.empty();
  @override
  Future<bool> restorePendingRecording() async {
    restores++;
    return false;
  }

  @override
  Stream<VoiceRecognitionEvent> start(VoiceRecognitionConfig config) {
    starts++;
    return events.stream;
  }

  @override
  Stream<VoiceRecognitionEvent> retryTranscription() {
    retries++;
    return events.stream;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> abortTranscription() async {
    aborts++;
  }

  @override
  Future<void> stop() {
    stops++;
    return stopped ?? Future.value();
  }

  @override
  Future<Map<String, Object?>> checkAccess({
    String? locale,
    bool request = false,
  }) async => access;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
