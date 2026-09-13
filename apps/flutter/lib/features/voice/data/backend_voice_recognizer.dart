import 'dart:async';
import 'dart:convert';

import 'package:app_voice/app_voice.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import 'voice_recording.dart';

typedef VoiceBackendInvoke = Future<Object?> Function(Map<String, Object?> body);

/// Records locally and sends audio only to the authenticated application backend.
class BackendVoiceRecognizer extends RecordedVoiceRecognizer
    implements RecordedVoiceAmplitudeSource {
  BackendVoiceRecognizer({
    required VoiceRecorder recorder,
    required VoiceRecordingStore store,
    required String? Function() ownerId,
    required VoiceBackendInvoke invoke,
    this.requestTimeout = const Duration(seconds: 75),
  }) : _recorder = recorder, _store = store, _ownerId = ownerId, _invoke = invoke;

  final VoiceRecorder _recorder;
  final VoiceRecordingStore _store;
  final String? Function() _ownerId;
  final VoiceBackendInvoke _invoke;
  final Duration requestTimeout;
  VoiceRecording? _pending;
  VoiceRecording? _capture;
  Future<void>? _finalizing;
  bool _recording = false;
  int _attempt = 0;
  int _discard = 0;

  @override
  Stream<double> get amplitudeDbfs => _recorder.amplitudeDbfs;
  @override
  bool get canRetryTranscription =>
      _pending != null && _pending!.ownerId == _ownerId();

  Future<bool> hasPermission({bool request = false}) =>
      _recorder.hasPermission(request: request);

  @override
  Future<bool> restorePendingRecording() async {
    if (_recording || _finalizing != null) return canRetryTranscription;
    final saved = _pending ?? await _store.load();
    _pending = saved?.ownerId == _ownerId() ? saved : null;
    return canRetryTranscription;
  }

  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    final owner = _ownerId();
    if (owner == null || owner.isEmpty) {
      throw const VoiceRecognitionException('speech_unavailable', 'Sign in to use voice transcription.');
    }
    if (!await _recorder.hasPermission()) {
      throw const VoiceRecognitionException('microphone_denied', 'Allow microphone access in the application or browser settings.');
    }
    await restorePendingRecording();
    await cancel(); // Starting again is an explicit replacement, unlike retry.
    final path = await _store.createPath();
    _capture = VoiceRecording(path: path, ownerId: owner, locale: config.locale);
    _recording = true;
    try {
      await _recorder.start(path);
    } catch (_) {
      await cancel();
      throw const VoiceRecognitionException('microphone_denied', 'The microphone could not be opened. Check permissions and the selected input device.');
    }
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) async {
    final attempt = ++_attempt;
    final finalizing = _finalize(_discard);
    _finalizing = finalizing;
    try { await finalizing; }
    finally { if (identical(_finalizing, finalizing)) _finalizing = null; }
    _checkAttempt(attempt);
    return retryTranscription();
  }

  Future<void> _finalize(int discard) async {
    final capture = _capture;
    final path = await _recorder.stop() ?? capture?.path;
    _recording = false;
    if (capture == null || path == null) {
      throw const VoiceRecognitionException('empty_recording', 'No audio was recorded.');
    }
    final recording = VoiceRecording(path: path, ownerId: capture.ownerId, locale: capture.locale);
    _capture = recording; // Also permits cleanup if stop raced with discard.
    if (discard != _discard) throw _canceled;
    _pending = recording; // Keep the original even if metadata persistence fails.
    await _store.save(recording);
  }

  @override
  Future<VoiceRecognitionTranscript> retryTranscription() async {
    final recording = _pending;
    if (recording == null || !canRetryTranscription) {
      throw const VoiceRecognitionException('empty_recording', 'No recording is available for this account.');
    }
    final attempt = ++_attempt;
    try {
      final bytes = await _store.read(recording);
      _checkAttempt(attempt);
      if (recording.ownerId != _ownerId()) throw _canceled;
      if (bytes.length <= 44 || bytes.length > 12 * 1024 * 1024) {
        throw const VoiceRecognitionException('invalid_audio', 'The recording is empty or exceeds the upload limit.');
      }
      final result = await _invoke({
        'input_audio': {'data': base64Encode(bytes), 'format': 'wav'},
        if (recording.locale != null) 'locale': recording.locale,
      }).timeout(requestTimeout);
      _checkAttempt(attempt);
      if (result is! Map || result['ok'] != true) {
        throw _backendError(result is Map ? result['code'] : null);
      }
      final text = result['text'];
      if (text is! String || text.trim().isEmpty || text.length > 32768) {
        throw const VoiceRecognitionException('speech_recognition_failed', 'No usable speech was recognized. Retry the saved recording.');
      }
      // There is no await between the final ownership check and storage deletion.
      if (recording.ownerId != _ownerId()) throw _canceled;
      await _store.remove(recording);
      _checkAttempt(attempt);
      _pending = null;
      _capture = null;
      return VoiceRecognitionTranscript(text: text.trim());
    } on VoiceRecognitionException {
      rethrow;
    } on TimeoutException {
      throw _backendError('transcription_timeout');
    } on FunctionException catch (error) {
      final details = error.details;
      throw _backendError(details is Map ? details['code'] : null);
    } catch (_) {
      // Never surface response bodies, credentials, file paths or audio in errors.
      throw const VoiceRecognitionException('speech_network_unavailable', 'Transcription could not complete. Retry the saved recording.');
    }
  }

  static const _canceled = VoiceRecognitionException('speech_canceled', 'Canceled.');
  void _checkAttempt(int attempt) { if (attempt != _attempt) throw _canceled; }

  static VoiceRecognitionException _backendError(Object? code) {
    final network = code == 'transcription_timeout' || code == 'transcription_failed';
    return VoiceRecognitionException(
      network ? 'speech_network_unavailable' : 'speech_unavailable',
      'Voice transcription is unavailable. Check your connection and retry the saved recording.',
    );
  }

  @override
  Future<void> abortTranscription() async {
    ++_attempt;
    try { await _finalizing; } catch (_) {}
    // AccountClient has no cancellation token. Generation checks reject late
    // results; the server independently aborts its bounded upstream request.
  }

  @override
  Future<void> cancel() async {
    ++_discard;
    await abortTranscription();
    try { if (_recording) await _recorder.cancel(); }
    finally {
      _recording = false;
      final recording = _pending ?? _capture;
      _pending = null;
      _capture = null;
      if (recording != null) await _store.remove(recording);
    }
  }

  @override
  void dispose() { unawaited(_recorder.dispose().catchError((Object _) {})); }
}
