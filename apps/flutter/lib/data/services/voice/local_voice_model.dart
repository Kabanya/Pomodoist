import 'package:pomodoist/domain/models/voice/whisper_model.dart';

typedef VoiceModelFile = ({String name, int size, String sha256});

extension WhisperModelManifest on WhisperModel {
  String get revision => switch (this) {
    WhisperModel.tiny => '65176e2deb88badc814a94058666cadccc29b61c',
    WhisperModel.base => 'bb53ee204431c90d314c1cc08d28d23e5b7927cc',
    WhisperModel.small => '8f3c18b358db4d1f2fc1eae49d75cd20989e4309',
  };
  String get origin =>
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-$name/resolve/$revision/';
  String get cacheName => 'pomodoist-whisper-$name-v1';

  List<VoiceModelFile> get files {
    final (encoderSize, encoderHash, decoderSize, decoderHash) = switch (this) {
      WhisperModel.tiny => (
        12937772,
        'd24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434',
        89855401,
        'd2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925',
      ),
      WhisperModel.base => (
        29120534,
        '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11',
        130672026,
        '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d',
      ),
      WhisperModel.small => (
        112442483,
        '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9',
        262226114,
        'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee',
      ),
    };
    return [
      (name: '$name-encoder.int8.onnx', size: encoderSize, sha256: encoderHash),
      (name: '$name-decoder.int8.onnx', size: decoderSize, sha256: decoderHash),
      (
        name: '$name-tokens.txt',
        size: 816730,
        sha256:
            'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
      ),
    ];
  }
}
