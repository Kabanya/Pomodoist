import 'dart:async';

import 'package:app_voice/app_voice.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/voice/android_system_voice_controller.dart';
import 'package:pomodoist/data/services/voice/voice_recording.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const events = MethodChannel('pomodoist/android_speech/events');
  const commands = MethodChannel('pomodoist/android_speech');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'Android voice forwards locale, input level, stop and final text',
    () async {
      final listening = Completer<Object?>();
      messenger.setMockMethodCallHandler(events, (call) async {
        if (call.method == 'listen') listening.complete(call.arguments);
        return null;
      });
      final actions = <String>[];
      messenger.setMockMethodCallHandler(commands, (call) async {
        actions.add(call.method);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(events, null);
        messenger.setMockMethodCallHandler(commands, null);
      });

      final controller = AndroidSystemVoiceController(
        permissions: _Permission(),
      );
      addTearDown(controller.dispose);
      final amplitude = controller.amplitudeDbfs.first;
      final result = controller
          .start(const VoiceRecognitionConfig(locale: 'ru-RU'))
          .toList();
      expect(await listening.future, 'ru-RU');
      await messenger.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope('recording'),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope(4.0),
        (_) {},
      );
      expect(await amplitude, -30);
      await controller.stop();
      expect(actions, ['stop']);
      await messenger.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope('transcribing'),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope({'text': 'Купить молоко'}),
        (_) {},
      );
      await messenger.handlePlatformMessage(events.name, null, (_) {});
      final states = await result;
      expect(states.map((state) => state.status), [
        VoiceRecognitionStatus.requestingPermission,
        VoiceRecognitionStatus.recording,
        VoiceRecognitionStatus.transcribing,
        VoiceRecognitionStatus.completed,
      ]);
      expect(states.last.finalText, 'Купить молоко');
    },
  );

  test(
    'declined microphone access reports an error without starting Android speech',
    () async {
      final controller = AndroidSystemVoiceController(
        permissions: _Permission(granted: false),
      );
      addTearDown(controller.dispose);
      final states = await controller
          .start(const VoiceRecognitionConfig())
          .toList();
      expect(states.last.error?.code, 'microphone_denied');
    },
  );
}

class _Permission implements VoiceRecorder {
  _Permission({this.granted = true});

  final bool granted;

  @override
  Future<bool> hasPermission({bool request = true}) async => granted;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
