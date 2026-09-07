import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_voice/app_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/voice/data/backend_voice_recognizer.dart';
import 'package:pomodoist/features/voice/data/pomodoist_voice_controller.dart';
import 'package:pomodoist/features/voice/data/voice_recording.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only native Apple runtimes keep system transcription', () {
    for (final platform in TargetPlatform.values) {
      expect(usesBackendVoice(isWeb: true, platform: platform), isTrue);
      expect(usesBackendVoice(isWeb: false, platform: platform),
          platform != TargetPlatform.iOS && platform != TargetPlatform.macOS);
    }
  });

  test('successful transcript is emitted into the existing controller flow', () async {
    final store = MemoryStore();
    final recorder = FakeRecorder();
    final recognizer = BackendVoiceRecognizer(
      recorder: recorder, store: store, ownerId: () => 'user',
      invoke: (body) async {
        expect(body['locale'], 'ru-RU');
        expect(body['input_audio'], {'data': base64Encode(store.audio), 'format': 'wav'});
        expect(body.containsKey('model'), isFalse);
        return {'ok': true, 'text': 'Купить молоко завтра'};
      },
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    final events = <VoiceRecognitionEvent>[];
    final done = Completer<void>();
    controller.start(const VoiceRecognitionConfig(locale: 'ru-RU')).listen(events.add, onDone: done.complete);
    await Future<void>.delayed(Duration.zero);
    await controller.stop();
    await done.future;
    expect(events.map((e) => e.status), [
      VoiceRecognitionStatus.requestingPermission, VoiceRecognitionStatus.recording,
      VoiceRecognitionStatus.transcribing, VoiceRecognitionStatus.completed,
    ]);
    expect(events.last.finalText, 'Купить молоко завтра');
    expect(recognizer.canRetryTranscription, isFalse);
    expect(store.pending, isNull);
    controller.dispose();
  });

  test('temporary failure preserves the original audio and locale for retry', () async {
    final store = MemoryStore();
    final requests = <Map<String, Object?>>[];
    final recognizer = BackendVoiceRecognizer(
      recorder: FakeRecorder(), store: store, ownerId: () => 'user',
      invoke: (body) async {
        requests.add(body);
        return requests.length == 1
            ? {'ok': false, 'code': 'transcription_timeout'}
            : {'ok': true, 'text': 'Recovered'};
      },
    );
    await recognizer.start(const VoiceRecognitionConfig(locale: 'fr-FR'));
    await expectLater(recognizer.stop(const VoiceRecognitionConfig(locale: 'fr-FR')), throwsA(isA<VoiceRecognitionException>()));
    expect(recognizer.canRetryTranscription, isTrue);
    expect(store.pending, isNotNull);
    expect((await recognizer.retryTranscription()).text, 'Recovered');
    expect(requests[0], requests[1]);
    expect(recognizer.canRetryTranscription, isFalse);
  });

  test('abort suppresses late results without deleting recoverable audio', () async {
    final response = Completer<Object?>();
    final store = MemoryStore();
    final recognizer = BackendVoiceRecognizer(recorder: FakeRecorder(), store: store, ownerId: () => 'user', invoke: (_) => response.future);
    await recognizer.start(const VoiceRecognitionConfig());
    final pending = recognizer.stop(const VoiceRecognitionConfig());
    final failed = expectLater(pending, throwsA(isA<VoiceRecognitionException>()));
    await Future<void>.delayed(Duration.zero);
    await recognizer.abortTranscription();
    response.complete({'ok': true, 'text': 'Late'});
    await failed;
    expect(recognizer.canRetryTranscription, isTrue);
    expect(store.pending, isNotNull);
  });

  test('explicit cancellation discards audio and rejects late results', () async {
    final response = Completer<Object?>();
    final store = MemoryStore();
    final recognizer = BackendVoiceRecognizer(recorder: FakeRecorder(), store: store, ownerId: () => 'user', invoke: (_) => response.future);
    await recognizer.start(const VoiceRecognitionConfig());
    final pending = recognizer.stop(const VoiceRecognitionConfig());
    final failed = expectLater(pending, throwsA(isA<VoiceRecognitionException>()));
    await Future<void>.delayed(Duration.zero);
    await recognizer.cancel();
    response.complete({'ok': true, 'text': 'Late'});
    await failed;
    expect(recognizer.canRetryTranscription, isFalse);
    expect(store.pending, isNull);
  });

  test('a new controller can restore a recording but another account cannot', () async {
    final store = MemoryStore()..pending = const VoiceRecording(path: '/recording.wav', ownerId: 'user', locale: 'ru-RU');
    var owner = 'other';
    var requests = 0;
    final recognizer = BackendVoiceRecognizer(recorder: FakeRecorder(), store: store, ownerId: () => owner, invoke: (_) async {
      requests++;
      return {'ok': true, 'text': 'Restored'};
    });
    expect(await recognizer.restorePendingRecording(), isFalse);
    await expectLater(recognizer.retryTranscription(), throwsA(isA<VoiceRecognitionException>()));
    expect(requests, 0);
    owner = 'user';
    expect(await recognizer.restorePendingRecording(), isTrue);
    expect((await recognizer.retryTranscription()).text, 'Restored');
  });

  test('denied microphone and signed-out state never start recording', () async {
    final recorder = FakeRecorder()..permission = false;
    var owner = 'user';
    final recognizer = BackendVoiceRecognizer(recorder: recorder, store: MemoryStore(), ownerId: () => owner, invoke: (_) async => null);
    await expectLater(recognizer.start(const VoiceRecognitionConfig()), throwsA(isA<VoiceRecognitionException>()));
    expect(recorder.starts, 0);
    recorder.permission = true;
    owner = '';
    await expectLater(recognizer.start(const VoiceRecognitionConfig()), throwsA(isA<VoiceRecognitionException>()));
    expect(recorder.starts, 0);
  });

  test('empty provider text and timeout both keep retryable audio', () async {
    for (final response in [Future<Object?>.value({'ok': true, 'text': ' '}), Completer<Object?>().future]) {
      final recognizer = BackendVoiceRecognizer(recorder: FakeRecorder(), store: MemoryStore(), ownerId: () => 'user', invoke: (_) => response, requestTimeout: const Duration(milliseconds: 5));
      await recognizer.start(const VoiceRecognitionConfig());
      await expectLater(recognizer.stop(const VoiceRecognitionConfig()), throwsA(isA<VoiceRecognitionException>()));
      expect(recognizer.canRetryTranscription, isTrue);
    }
  });

  test('cancel during recorder finalization discards the stopped file', () async {
    final recorder = FakeRecorder()..stopping = Completer<String?>();
    final store = MemoryStore();
    var requests = 0;
    final recognizer = BackendVoiceRecognizer(recorder: recorder, store: store, ownerId: () => 'user', invoke: (_) async {
      requests++;
      return {'ok': true, 'text': 'Must not run'};
    });
    await recognizer.start(const VoiceRecognitionConfig());
    final pending = recognizer.stop(const VoiceRecognitionConfig());
    final failure = expectLater(pending, throwsA(isA<VoiceRecognitionException>()));
    final canceling = recognizer.cancel();
    recorder.stopping!.complete(recorder.path);
    await canceling;
    await failure;
    expect(store.pending, isNull);
    expect(requests, 0);
  });

  test('backend permissions do not require Apple Speech authorization', () async {
    final recorder = FakeRecorder()..permission = false;
    final controller = BackendVoiceController(BackendVoiceRecognizer(recorder: recorder, store: MemoryStore(), ownerId: () => 'user', invoke: (_) async => null));
    expect(await controller.checkAccess(), {'microphone': 'notDetermined', 'speech': 'authorized'});
    expect(await controller.checkAccess(request: true), {'microphone': 'denied', 'speech': 'authorized'});
    recorder.permission = true;
    expect(await controller.checkAccess(), {'microphone': 'authorized', 'speech': 'authorized'});
    controller.dispose();
  });

  test('configured recording limit is enforced by the existing controller', () async {
    final recorder = FakeRecorder();
    final controller = VoiceRecognitionController(
      recordedRecognizer: BackendVoiceRecognizer(recorder: recorder, store: MemoryStore(), ownerId: () => 'user', invoke: (_) async => {'ok': true, 'text': 'Auto stopped'}),
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    final events = await controller.start(const VoiceRecognitionConfig(maxDuration: Duration(milliseconds: 5))).toList();
    expect(recorder.stops, 1);
    expect(events.last.finalText, 'Auto stopped');
    controller.dispose();
  });
}

class FakeRecorder implements VoiceRecorder {
  bool permission = true;
  int starts = 0;
  int stops = 0;
  String? path;
  Completer<String?>? stopping;
  @override
  Stream<double> get amplitudeDbfs => const Stream.empty();
  @override
  Future<bool> hasPermission({bool request = true}) async => permission;
  @override
  Future<void> start(String path) async { starts++; this.path = path; }
  @override
  Future<String?> stop() async { stops++; return stopping == null ? path : await stopping!.future; }
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

class MemoryStore implements VoiceRecordingStore {
  final audio = Uint8List.fromList(List.generate(100, (i) => i));
  VoiceRecording? pending;
  @override
  Future<String> createPath() async => '/recording.wav';
  @override
  Future<VoiceRecording?> load() async => pending;
  @override
  Future<void> save(VoiceRecording recording) async { pending = recording; }
  @override
  Future<Uint8List> read(VoiceRecording recording) async => audio;
  @override
  Future<void> remove(VoiceRecording recording) async { pending = null; }
}
