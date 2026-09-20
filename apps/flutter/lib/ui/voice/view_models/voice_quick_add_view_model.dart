import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/voice_dependencies.dart';
import 'package:pomodoist/config/voice_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/voice/voice_capture_repository.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'package:pomodoist/domain/models/voice/voice_quick_add_state.dart';

final voiceQuickAddViewModelProvider = NotifierProvider.autoDispose
    .family<VoiceQuickAddViewModel, VoiceQuickAddState, Object>(
      VoiceQuickAddViewModel.new,
    );

/// Owns the editable drafts and panel presentation for one retained session.
///
/// Device capture and transcription live behind [VoiceCaptureRepository].
/// Drafts, draft revision, analysis and the saving flag stay here so they
/// survive rebuilds and never outlive the overlay.
class VoiceQuickAddViewModel extends Notifier<VoiceQuickAddState> {
  VoiceQuickAddViewModel(this.session);
  final Object session;

  late final VoiceCaptureRepository _capture;
  VoiceCaptureState _captureState = const VoiceCaptureState();
  String _locale = 'en';
  bool _smartMode = false;
  List<DecomposedTaskDraft> _drafts = const [];
  int _draftRevision = 0;
  Object? _analysisError;
  bool _analyzing = false;
  bool _saving = false;
  int? _accountGeneration;

  @override
  VoiceQuickAddState build() {
    final capture = ref.watch(voiceCaptureRepositoryProvider(session));
    final captureState = capture.currentState;
    final captureSubscription = capture.watchState().listen(_onCaptureState);
    ref.onDispose(captureSubscription.cancel);
    ref.listen<bool>(voiceSmartModeProvider, (_, next) {
      _smartMode = next;
      _emit();
    });
    ref.listen(accountSessionProvider, (_, next) {
      _accountGeneration = next.value?.generation;
    }, fireImmediately: true);
    _capture = capture;
    _captureState = captureState;
    _smartMode = ref.read(voiceSmartModeProvider);
    return _state;
  }

  VoiceQuickAddState get _state => VoiceQuickAddState(
    status: _captureState.status,
    transcript: _captureState.transcript,
    error: _analysisError ?? _captureError,
    recognitionErrorMessage: _captureState.recognitionErrorMessage,
    voiceErrorCode: _captureState.voiceErrorCode,
    restoring: _captureState.restoring,
    accessBusy: _captureState.accessBusy,
    analyzing: _analyzing,
    saving: _saving,
    stopping: _captureState.stopping,
    captureActive: _captureState.capturing,
    smartMode: _smartMode,
    amplitudeLevel: _captureState.amplitudeLevel,
    recordingSecondsRemaining: _captureState.recordingSecondsRemaining,
    isCapturing: _captureState.isCapturing,
    isTranscribing: _captureState.isTranscribing,
    canStart: _captureState.canStart && !_analyzing && !_saving,
    motionActive: _captureState.motionActive || _analyzing,
    canUseCloudFallback: _captureState.canUseCloudFallback,
    needsPermissionRequest: _captureState.needsPermissionRequest,
    settingsDestination: _captureState.settingsDestination,
    canRetryTranscription: _captureState.canRetryTranscription,
    cloudMode: _captureState.cloudMode,
    drafts: _drafts,
    draftRevision: _draftRevision,
  );

  VoiceQuickAddError? get _captureError => switch (_captureState.failure) {
    null => null,
    VoiceCaptureFailure.general => VoiceQuickAddError.general,
    VoiceCaptureFailure.settings => VoiceQuickAddError.settings,
    VoiceCaptureFailure.restricted => VoiceQuickAddError.restricted,
    VoiceCaptureFailure.microphoneDenied => VoiceQuickAddError.microphoneDenied,
    VoiceCaptureFailure.speechDenied => VoiceQuickAddError.speechDenied,
    VoiceCaptureFailure.recognition => VoiceQuickAddError.recognition,
  };

  void _emit() {
    if (!ref.mounted) return;
    state = _state;
  }

  void _onCaptureState(VoiceCaptureState next) {
    final previous = _captureState;
    _captureState = next;
    if (next.capturing && !previous.capturing) {
      _drafts = const [];
      _draftRevision++;
      _analysisError = null;
      _analyzing = false;
    }
    if (next.status == VoiceCaptureStatus.completed &&
        previous.status != VoiceCaptureStatus.completed &&
        next.transcript.trim().isNotEmpty) {
      unawaited(decomposeTranscript(next.transcript));
    }
    _emit();
  }

  void setLocale(String locale) => _locale = locale;

  Future<void> loadSmartMode() async {
    final result = await ref.read(voicePreferencesRepositoryProvider).ready;
    result.getOrThrow();
  }

  Future<void> setSmartMode(bool value) async {
    final result = await ref
        .read(voicePreferencesRepositoryProvider)
        .setSmartMode(value);
    try {
      result.getOrThrow();
    } catch (_) {
      _analysisError = VoiceQuickAddError.general;
      _emit();
    }
  }

  Future<void> restoreRecording() =>
      _capture.restore().then((result) => result.getOrThrow());

  Future<void> start({bool retry = false}) => _capture
      .start(_locale, retry: retry)
      .then((result) => result.getOrThrow());

  Future<void> stop() => _capture.stop().then((result) => result.getOrThrow());

  Future<bool> closeVoice() async {
    if (_saving) return false;
    return (await _capture.close()).getOrThrow();
  }

  Future<void> refreshAccess({bool request = false}) => _capture
      .refreshAccess(locale: _locale, request: request)
      .then((result) => result.getOrThrow());

  Future<void> recoverAccess() =>
      _capture.recoverAccess(_locale).then((result) => result.getOrThrow());

  Future<void> useCloudTranscription() => _capture
      .useCloudTranscription(_locale)
      .then((result) => result.getOrThrow());

  Future<void> decomposeTranscript(String transcript) async {
    final decomposer = ref.read(taskDecomposerProvider);
    final now = ref.read(clockProvider).now();
    final accountGeneration = ref
        .read(accountSessionProvider)
        .value
        ?.generation;
    _analysisError = null;
    _analyzing = true;
    _drafts = const [];
    _draftRevision++;
    _emit();
    List<DecomposedTaskDraft> drafts;
    Object? failure;
    try {
      final tasks = await decomposer.decompose(
        transcript,
        now: now,
        locale: _locale,
        smartMode: _smartMode,
      );
      if (!ref.mounted) return;
      drafts = tasks.isEmpty ? fallbackQuickAddTasks(transcript) : tasks;
    } catch (exception) {
      if (!ref.mounted) return;
      failure = exception is TaskDecompositionException
          ? exception.message
          : VoiceQuickAddError.fallback;
      drafts = fallbackQuickAddTasks(transcript);
    }
    if (!ref.mounted) return;
    if (accountGeneration != null && accountGeneration != _accountGeneration) {
      _analyzing = false;
      _emit();
      return;
    }
    _analysisError = failure;
    _drafts = List.unmodifiable(drafts);
    _draftRevision++;
    _analyzing = false;
    _emit();
  }

  Future<List<String>?> save(
    List<DecomposedTaskDraft> drafts, {
    int? defaultPriority,
    DateTime? defaultDate,
    String? projectId,
    String? kanbanStatusId,
    String? labelId,
  }) async {
    if (!state.canStart || _saving || drafts.isEmpty) return null;
    final save = ref.read(saveVoiceDraftsProvider);
    _saving = true;
    _emit();
    try {
      return await save(
        drafts,
        defaultPriority: defaultPriority,
        defaultDate: defaultDate,
        projectId: projectId,
        kanbanStatusId: kanbanStatusId,
        labelId: labelId,
      );
    } finally {
      if (ref.mounted) {
        _saving = false;
        _emit();
      }
    }
  }
}

final voiceAccessViewModelProvider =
    AsyncNotifierProvider.autoDispose<VoiceAccessViewModel, bool>(
      VoiceAccessViewModel.new,
    );

class VoiceAccessViewModel extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      ref.watch(billingAccessProvider).value?.hasActiveEntitlement ?? false;
  Future<bool> check() async {
    final keepAlive = ref.keepAlive();
    try {
      var access = ref.read(billingAccessProvider).value;
      if (access == null || access.loading) {
        await ref.read(billingRepositoryProvider).refresh();
        if (!ref.mounted) return false;
        access = ref.read(billingAccessProvider).value;
      }
      return access?.hasActiveEntitlement ?? false;
    } finally {
      keepAlive.close();
    }
  }
}

final voiceDraftViewModelProvider = NotifierProvider.autoDispose
    .family<VoiceDraftViewModel, ParsedQuickAdd, (String, DateTime?)>(
      VoiceDraftViewModel.new,
    );

class VoiceDraftViewModel extends Notifier<ParsedQuickAdd> {
  VoiceDraftViewModel(this.input);
  final (String, DateTime?) input;
  @override
  ParsedQuickAdd build() => ref
      .watch(quickAddParserProvider)
      .parse(
        input.$1,
        now: ref.read(clockProvider).now(),
        defaultDate: input.$2,
      );
}
