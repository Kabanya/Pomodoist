import 'package:pomodoist/domain/models/voice/whisper_model.dart';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:app_voice/app_voice.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:pomodoist/data/services/voice/local_voice_audio.dart';
import 'package:pomodoist/data/services/voice/local_voice_desktop_decoder.dart';
import 'package:pomodoist/data/services/voice/local_voice_model.dart';
import 'package:pomodoist/data/services/voice/voice_recording.dart';

Future<Directory> _directory(WhisperModel tier) async => Directory(
  p.join((await getApplicationCacheDirectory()).path, tier.cacheName),
);

Future<bool> isVoiceModelReady(WhisperModel tier) async {
  try {
    return await _verified(await _directory(tier), tier);
  } on Exception {
    // An inaccessible cache cannot satisfy a recording request.
    return false;
  }
}

Future<bool> _verified(Directory directory, WhisperModel tier) async {
  for (final model in tier.files) {
    if (!await _validModel(
      File(p.join(directory.path, model.name)),
      model.size,
      model.sha256,
    )) {
      return false;
    }
  }
  return true;
}

Future<String> transcribeLocally(
  Uint8List pcm,
  String? locale,
  Future<void> cancellation, {
  WhisperModel tier = WhisperModel.tiny,
}) async {
  final segments = localVoiceSegments(pcm, voicePcmSampleRate);
  if (segments.isEmpty) return '';
  final directory = await _directory(tier);
  final verified = await Future.any([
    _verified(directory, tier),
    cancellation.then<bool>(
      (_) => throw const VoiceRecognitionException(
        'speech_canceled',
        'Local recognition was canceled.',
      ),
    ),
  ]);
  if (!verified) {
    throw const VoiceRecognitionException(
      'voice_model_download_failed',
      'Model unavailable',
    );
  }
  final path = directory.path;
  return Isolate.run(() => _decode(path, segments, locale, tier));
}

Future<void> downloadVoiceModel(
  WhisperModel tier,
  void Function(double) progress,
) async {
  final client = http.Client();
  Directory? temporary;
  try {
    final directory = await (await _directory(tier)).create(recursive: true);
    final total = tier.files.fold(0, (sum, file) => sum + file.size);
    var verified = 0;
    for (final model in tier.files) {
      final target = File(p.join(directory.path, model.name));
      if (await _validModel(target, model.size, model.sha256)) {
        verified += model.size;
        progress(verified / total);
        continue;
      }
      temporary ??= await directory.createTemp('download-');
      final download = File(p.join(temporary.path, model.name));
      final response = await client
          .send(http.Request('GET', Uri.parse('${tier.origin}${model.name}')))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const HttpException('Model unavailable');
      }
      final sink = download.openWrite();
      try {
        var received = 0;
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          received += chunk.length;
          if (received > model.size) {
            throw const FormatException('Unexpected model size');
          }
          sink.add(chunk);
          progress((verified + received) / total);
        }
      } finally {
        await sink.close();
      }
      if (!await _validModel(download, model.size, model.sha256)) {
        throw const FormatException('Invalid speech model');
      }
      await download.rename(target.path);
      verified += model.size;
    }
  } catch (_) {
    throw const VoiceRecognitionException(
      'voice_model_download_failed',
      'The speech model could not be downloaded.',
    );
  } finally {
    client.close();
    try {
      await temporary?.delete(recursive: true);
    } on FileSystemException {
      // A stale temporary directory never replaces the validated model.
    }
  }
}

Future<bool> _validModel(File file, int size, String expected) async =>
    await file.exists() &&
    await file.length() == size &&
    (await sha256.bind(file.openRead()).first).toString() == expected;

String _decode(
  String path,
  List<Float32List> segments,
  String? locale,
  WhisperModel tier,
) {
  final executable = p.dirname(Platform.resolvedExecutable);
  final String libraries;
  final String sherpa;
  final String bridge;
  if (Platform.isLinux) {
    libraries = p.join(executable, 'lib');
    // The Sherpa library needs its bundled ONNX Runtime from the same directory.
    DynamicLibrary.open(p.join(libraries, 'libonnxruntime.so'));
    sherpa = 'libsherpa-onnx-c-api.so';
    bridge = 'libpomodoist_local_speech.so';
  } else {
    libraries = executable;
    sherpa = 'sherpa-onnx-c-api.dll';
    bridge = 'pomodoist_local_speech.dll';
  }
  return decodeDesktopVoice(
    bridge: DynamicLibrary.open(p.join(libraries, bridge)),
    sherpa: DynamicLibrary.open(p.join(libraries, sherpa)),
    encoder: p.join(path, tier.files[0].name),
    decoder: p.join(path, tier.files[1].name),
    tokens: p.join(path, tier.files[2].name),
    language: locale?.split(RegExp('[-_]')).first.toLowerCase() ?? '',
    sampleRate: voicePcmSampleRate,
    segments: segments,
  );
}
