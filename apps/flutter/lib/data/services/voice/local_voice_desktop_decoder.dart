import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// The matching native bridge owns the versioned Sherpa-ONNX config struct.
typedef _Handle = Pointer<Void>;
typedef _CreateRecognizer = NativeFunction<_Handle Function(_Handle)>;
typedef _CreateWhisper =
    _Handle Function(
      Pointer<_CreateRecognizer>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );

String decodeDesktopVoice({
  required DynamicLibrary bridge,
  required DynamicLibrary sherpa,
  required String encoder,
  required String decoder,
  required String tokens,
  required String language,
  required int sampleRate,
  required List<Float32List> segments,
}) {
  final createRecognizer = sherpa.lookup<_CreateRecognizer>(
    'SherpaOnnxCreateOfflineRecognizer',
  );
  final createWhisper = bridge.lookupFunction<_CreateWhisper, _CreateWhisper>(
    'PomodoistCreateWhisperRecognizer',
  );
  final destroyRecognizer = sherpa
      .lookupFunction<Void Function(_Handle), void Function(_Handle)>(
        'SherpaOnnxDestroyOfflineRecognizer',
      );
  final createStream = sherpa
      .lookupFunction<_Handle Function(_Handle), _Handle Function(_Handle)>(
        'SherpaOnnxCreateOfflineStream',
      );
  final destroyStream = sherpa
      .lookupFunction<Void Function(_Handle), void Function(_Handle)>(
        'SherpaOnnxDestroyOfflineStream',
      );
  final acceptAudio = sherpa
      .lookupFunction<
        Void Function(_Handle, Int32, Pointer<Float>, Int32),
        void Function(_Handle, int, Pointer<Float>, int)
      >('SherpaOnnxAcceptWaveformOffline');
  final decode = sherpa
      .lookupFunction<
        Void Function(_Handle, _Handle),
        void Function(_Handle, _Handle)
      >('SherpaOnnxDecodeOfflineStream');
  final resultJson = sherpa
      .lookupFunction<
        Pointer<Utf8> Function(_Handle),
        Pointer<Utf8> Function(_Handle)
      >('SherpaOnnxGetOfflineStreamResultAsJson');
  final freeResult = sherpa
      .lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('SherpaOnnxDestroyOfflineStreamResultJson');

  final recognizer = using(
    (arena) => createWhisper(
      createRecognizer,
      encoder.toNativeUtf8(allocator: arena),
      decoder.toNativeUtf8(allocator: arena),
      tokens.toNativeUtf8(allocator: arena),
      language.toNativeUtf8(allocator: arena),
    ),
  );
  if (recognizer == nullptr) {
    throw StateError('Cannot initialize speech recognition');
  }
  try {
    final text = <String>[];
    for (final samples in segments) {
      final stream = createStream(recognizer);
      if (stream == nullptr) {
        throw StateError('Cannot initialize speech stream');
      }
      try {
        using((arena) {
          final audio = arena<Float>(samples.length);
          audio.asTypedList(samples.length).setAll(0, samples);
          acceptAudio(stream, sampleRate, audio, samples.length);
        });
        decode(recognizer, stream);
        final result = resultJson(stream);
        if (result == nullptr) continue;
        try {
          final value = jsonDecode(result.toDartString());
          final transcript = value is Map ? value['text'] : null;
          if (transcript is String && transcript.trim().isNotEmpty) {
            text.add(transcript.trim());
          }
        } finally {
          freeResult(result);
        }
      } finally {
        destroyStream(stream);
      }
    }
    return text.join(' ');
  } finally {
    destroyRecognizer(recognizer);
  }
}
