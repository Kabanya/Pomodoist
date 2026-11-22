import 'package:pomodoist/domain/models/voice/whisper_model.dart';
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:app_voice/app_voice.dart';
import 'package:web/web.dart' as web;

import 'package:pomodoist/data/services/voice/local_voice_audio.dart';
import 'package:pomodoist/data/services/voice/local_voice_model.dart';
import 'package:pomodoist/data/services/voice/voice_recording.dart';

Future<String> transcribeLocally(
  Uint8List pcm,
  String? locale,
  Future<void> cancellation, {
  WhisperModel tier = WhisperModel.tiny,
}) async {
  final segments = localVoiceSegments(pcm, voicePcmSampleRate);
  if (segments.isEmpty) return '';
  return _modelWorker(
    tier,
    'recognize',
    cancellation: cancellation,
    segments: segments,
    locale: locale,
  );
}

Future<bool> isVoiceModelReady(WhisperModel tier) async {
  try {
    return (await _modelWorker(tier, 'check')) == 'ready';
  } on Exception {
    return false;
  }
}

Future<void> downloadVoiceModel(
  WhisperModel tier,
  void Function(double) progress,
) async {
  await _modelWorker(tier, 'download', progress: progress);
}

Future<String> _modelWorker(
  WhisperModel tier,
  String operation, {
  void Function(double)? progress,
  Future<void>? cancellation,
  List<Float32List> segments = const [],
  String? locale,
}) async {
  final worker = web.Worker(
    Uri.parse(
      web.document.baseURI,
    ).resolve('voice_recognition_worker.js').toString().toJS,
  );
  final result = Completer<String>();
  worker.onmessage = (web.MessageEvent event) {
    if (result.isCompleted) return;
    final message = _WorkerResult(event.data as JSObject);
    if (message.progress case final value?) {
      progress?.call(value);
      return;
    }
    if (message.code case final code?) {
      result.completeError(
        VoiceRecognitionException(code, 'Local speech recognition failed.'),
      );
    } else {
      result.complete(message.text ?? '');
    }
  }.toJS;
  worker.onerror = (web.Event event) {
    if (!result.isCompleted) {
      result.completeError(
        const VoiceRecognitionException(
          'speech_unavailable',
          'Local speech recognition failed.',
        ),
      );
    }
  }.toJS;
  try {
    worker.postMessage(
      {
        'operation': operation,
        'cacheName': tier.cacheName,
        'rate': voicePcmSampleRate,
        'segments': [for (final segment in segments) segment.toJS].toJS,
        'language': locale?.split(RegExp('[-_]')).first.toLowerCase() ?? '',
        'modelOrigin': tier.origin,
        'models': [
          for (final model in tier.files)
            {'name': model.name, 'size': model.size, 'sha256': model.sha256},
        ],
      }.jsify(),
    );
    if (operation == 'download') return await result.future;
    return await Future.any([
      result.future,
      if (cancellation != null)
        cancellation.then<String>(
          (_) => throw const VoiceRecognitionException(
            'speech_canceled',
            'Local recognition was canceled.',
          ),
        ),
    ]).timeout(const Duration(minutes: 10));
  } finally {
    worker.terminate();
  }
}

extension type _WorkerResult(JSObject _) implements JSObject {
  external double? get progress;
  external String? get code;
  external String? get text;
}
