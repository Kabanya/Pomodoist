import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'voice_recording.dart';

VoiceRecordingStore createVoiceRecordingStore() => FileVoiceRecordingStore();

/// Only this directory is owned by the backend transcription adapter.
class FileVoiceRecordingStore implements VoiceRecordingStore {
  FileVoiceRecordingStore({Future<Directory> Function()? directory})
      : _directoryLoader = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directoryLoader;
  Directory? _directory;
  static final _fileName = RegExp(r'^recording_[0-9]+\.wav$');

  Future<Directory> _storage() async {
    final existing = _directory;
    if (existing != null) return existing;
    final parent = await _directoryLoader();
    return _directory = await Directory(p.join(parent.path, 'pomodoist_voice_pending')).create(recursive: true);
  }

  @override
  Future<String> createPath() async => p.join(
    (await _storage()).path,
    'recording_${DateTime.now().microsecondsSinceEpoch}.wav',
  );

  @override
  Future<VoiceRecording?> load() async {
    final directory = await _storage();
    final manifest = File(p.join(directory.path, 'recording.json'));
    if (!await manifest.exists()) return null;
    try {
      final data = jsonDecode(await manifest.readAsString());
      if (data is! Map || data['file'] is! String || !_fileName.hasMatch(data['file'] as String) ||
          data['ownerId'] is! String || (data['locale'] != null && data['locale'] is! String)) return null;
      final path = p.join(directory.path, data['file'] as String);
      final file = File(path);
      if (!await file.exists() || await file.length() <= 44) return null;
      return VoiceRecording(path: path, ownerId: data['ownerId'] as String, locale: data['locale'] as String?);
    } on FormatException { return null; }
  }

  @override
  Future<void> save(VoiceRecording recording) async {
    final directory = await _storage();
    final file = File(recording.path);
    final name = p.basename(file.path);
    if (!_fileName.hasMatch(name) || !p.equals(file.parent.path, directory.path) || await file.length() <= 44) {
      throw const FormatException('Invalid recording');
    }
    final manifest = File(p.join(directory.path, 'recording.json'));
    final temporary = File('${manifest.path}.tmp');
    temporary.writeAsStringSync(jsonEncode({
      'file': name, 'ownerId': recording.ownerId, 'locale': recording.locale,
    }), flush: true);
    temporary.renameSync(manifest.path);
  }

  @override
  Future<Uint8List> read(VoiceRecording recording) async {
    final directory = await _storage();
    final file = File(recording.path);
    if (!p.equals(file.parent.path, directory.path) || !_fileName.hasMatch(p.basename(file.path))) {
      throw const FormatException('Invalid recording');
    }
    if (await file.length() > 12 * 1024 * 1024) throw const FormatException('Recording too large');
    return file.readAsBytes();
  }

  @override
  Future<void> remove(VoiceRecording recording) {
    final directory = _directory;
    if (directory == null) return Future<void>.value();
    final file = File(recording.path);
    final name = p.basename(file.path);
    if (!p.equals(file.parent.path, directory.path) || !_fileName.hasMatch(name)) return Future<void>.value();
    // Synchronous final deletion keeps discard atomic on the Dart isolate.
    final manifest = File(p.join(directory.path, 'recording.json'));
    if (manifest.existsSync()) {
      try {
        final data = jsonDecode(manifest.readAsStringSync());
        if (data is Map && data['file'] == name) manifest.deleteSync();
      } on FormatException { manifest.deleteSync(); }
    }
    if (file.existsSync()) file.deleteSync();
    return Future<void>.value();
  }
}
