import 'dart:async';

import 'package:app_voice/app_voice.dart';
import 'package:flutter/services.dart';

import 'package:pomodoist/data/services/voice/record_voice_recorder.dart';
import 'package:pomodoist/data/services/voice/voice_recording.dart';

/// Uses Android's on-device recognizer and its speech endpointer.
class AndroidSystemVoiceController implements VoiceRecognitionController {
  AndroidSystemVoiceController({VoiceRecorder? permissions})
    : _permissions = permissions ?? RecordVoiceRecorder();

  static const _commands = MethodChannel('pomodoist/android_speech');
  static const _events = EventChannel('pomodoist/android_speech/events');
  final VoiceRecorder _permissions;
  final _amplitude = StreamController<double>.broadcast();
  int _generation = 0;
  int? _nativeSession;

  @override
  Stream<double> get amplitudeDbfs => _amplitude.stream;

  @override
  bool get canRetryTranscription => false;

  @override
  Stream<VoiceRecognitionEvent> retryTranscription() =>
      throw StateError('Android system dictation does not save a recording.');

  @override
  Future<bool> restorePendingRecording() async => false;

  @override
  Future<Map<String, Object?>> checkAccess({
    String? locale,
    bool request = false,
  }) async {
    final granted = await _permissions.hasPermission(request: request);
    return {
      'microphone': granted
          ? 'authorized'
          : (request ? 'denied' : 'notDetermined'),
      'speech': 'authorized',
    };
  }

  @override
  Future<bool> openSettings(VoiceSettingsDestination destination) async =>
      await const MethodChannel(
        'pomodoist/voice_settings',
      ).invokeMethod<bool>('openMicrophoneSettings') ??
      false;

  @override
  Stream<VoiceRecognitionEvent> start(VoiceRecognitionConfig config) async* {
    final session = ++_generation;
    yield VoiceRecognitionEvent.requestingPermission;
    Timer? limit;
    try {
      final granted = await _permissions.hasPermission();
      if (session != _generation) return;
      if (!granted) {
        yield _error('microphone_denied');
        return;
      }
      _nativeSession = session;
      limit = Timer(config.maxDuration, () {
        unawaited(stop().catchError((Object _) {}));
      });
      await for (final event in _events.receiveBroadcastStream(config.locale)) {
        if (session != _generation) break;
        switch (event) {
          case 'recording':
            yield VoiceRecognitionEvent.recording;
          case 'transcribing':
            yield VoiceRecognitionEvent.transcribing;
          case {'text': final String text}:
            yield VoiceRecognitionEvent.completed(text: text);
          case final num rms:
            _amplitude.add((rms.toDouble() - 10) * 5);
        }
      }
    } on PlatformException catch (error) {
      if (session == _generation) yield _error(error.code);
    } catch (_) {
      if (session == _generation) yield _error('speech_system_unavailable');
    } finally {
      limit?.cancel();
      if (_nativeSession == session) _nativeSession = null;
    }
  }

  static VoiceRecognitionEvent _error(String code) =>
      VoiceRecognitionEvent.error(
        VoiceRecognitionError(code: code, message: code),
      );

  @override
  Future<void> stop() async {
    if (_nativeSession != null) await _commands.invokeMethod<void>('stop');
  }

  @override
  Future<void> abortTranscription() => cancel();

  @override
  Future<void> cancel() async {
    ++_generation;
    if (_nativeSession == null) return;
    _nativeSession = null;
    await _commands.invokeMethod<void>('cancel');
  }

  @override
  void dispose() {
    unawaited(
      cancel().catchError((Object _) {}).whenComplete(() async {
        await _amplitude.close();
        await _permissions.dispose();
      }),
    );
  }
}
