import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'voice_recording.dart';

// Retain across controller/overlay disposal, but never persist sensitive audio
// in localStorage. A browser refresh or closing the tab discards it.
final _store = BrowserVoiceRecordingStore();
VoiceRecordingStore createVoiceRecordingStore() => _store;

class BrowserVoiceRecordingStore implements VoiceRecordingStore {
  VoiceRecording? _pending;
  Uint8List? _bytes;
  @override
  Future<String> createPath() async => 'voice_${DateTime.now().microsecondsSinceEpoch}.wav';
  @override
  Future<VoiceRecording?> load() async => _pending;
  @override
  Future<void> save(VoiceRecording recording) async {
    final bytes = await _readBlob(recording.path);
    if (bytes.length <= 44 || bytes.length > 12 * 1024 * 1024) throw const FormatException('Invalid recording');
    final previous = _pending;
    _pending = recording;
    _bytes = bytes; // Independent of the recorder's blob URL lifetime.
    if (previous != null && previous.path != recording.path) web.URL.revokeObjectURL(previous.path);
  }
  @override
  Future<Uint8List> read(VoiceRecording recording) async {
    if (_pending?.path == recording.path && _bytes != null) {
      return _bytes!;
    }
    return _readBlob(recording.path);
  }
  Future<Uint8List> _readBlob(String path) async {
    if (!path.startsWith('blob:')) throw const FormatException('Invalid recording URL');
    final response = await web.window.fetch(path.toJS).toDart;
    if (!response.ok) throw const FormatException('Recording unavailable');
    return (await response.arrayBuffer().toDart).toDart.asUint8List();
  }
  @override
  Future<void> remove(VoiceRecording recording) async {
    if (_pending?.path == recording.path) { _pending = null; _bytes = null; }
    if (recording.path.startsWith('blob:')) web.URL.revokeObjectURL(recording.path);
  }
}
