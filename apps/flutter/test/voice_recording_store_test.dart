import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/voice/data/voice_recording.dart';
import 'package:pomodoist/features/voice/data/voice_recording_store_io.dart';

void main() {
  late Directory temporary;
  late FileVoiceRecordingStore store;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('pomodoist_voice_test_');
    store = FileVoiceRecordingStore(directory: () async => temporary);
  });
  tearDown(() async => temporary.delete(recursive: true));

  test('persists the original recording and locale across store instances', () async {
    final path = await store.createPath();
    final bytes = List.generate(100, (i) => i);
    await File(path).writeAsBytes(bytes);
    final recording = VoiceRecording(path: path, ownerId: 'user', locale: 'ru-RU');
    await store.save(recording);
    final restoredStore = FileVoiceRecordingStore(directory: () async => temporary);
    final restored = await restoredStore.load();
    expect(restored?.path, path);
    expect(restored?.ownerId, 'user');
    expect(restored?.locale, 'ru-RU');
    expect(await restoredStore.read(restored!), bytes);
    await restoredStore.remove(restored);
    expect(await File(path).exists(), isFalse);
    expect(await restoredStore.load(), isNull);
  });

  test('invalid metadata cannot reference or delete files outside the owned directory', () async {
    final outside = File('${temporary.path}/outside.wav');
    await outside.writeAsBytes(List.filled(100, 0));
    await store.createPath();
    final manifest = File('${temporary.path}/pomodoist_voice_pending/recording.json');
    await manifest.writeAsString(jsonEncode({'file': '../outside.wav', 'ownerId': 'user'}));
    expect(await store.load(), isNull);
    await store.remove(VoiceRecording(path: outside.path, ownerId: 'user'));
    expect(await outside.exists(), isTrue);
  });

  test('empty and missing recordings are not restored', () async {
    final path = await store.createPath();
    final manifest = File('${temporary.path}/pomodoist_voice_pending/recording.json');
    await manifest.writeAsString(jsonEncode({'file': File(path).uri.pathSegments.last, 'ownerId': 'user'}));
    expect(await store.load(), isNull);
    await File(path).writeAsBytes([]);
    expect(await store.load(), isNull);
  });
}
