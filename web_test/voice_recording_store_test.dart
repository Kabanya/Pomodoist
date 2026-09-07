import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:pomodoist/features/voice/data/voice_recording.dart';
import 'package:pomodoist/features/voice/data/voice_recording_store_web.dart';

void main() {
  test('browser retains bytes after recorder URL disposal until explicit discard', () async {
    final bytes = Uint8List.fromList(List.generate(100, (i) => i));
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'audio/wav'));
    final url = web.URL.createObjectURL(blob);
    final recording = VoiceRecording(path: url, ownerId: 'user', locale: 'ru-RU');
    final store = createVoiceRecordingStore();
    await store.save(recording);
    web.URL.revokeObjectURL(url);
    final restoredStore = createVoiceRecordingStore();
    expect((await restoredStore.load())?.locale, 'ru-RU');
    expect(await restoredStore.read(recording), bytes);
    await restoredStore.remove(recording);
    expect(await restoredStore.load(), isNull);
  });
}
