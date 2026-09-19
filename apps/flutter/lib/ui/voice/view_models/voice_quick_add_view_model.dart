import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/voice_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/data/repositories/voice/voice_quick_add_repository.dart';
import 'package:pomodoist/domain/models/voice/voice_quick_add_state.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';

final voiceQuickAddViewModelProvider = NotifierProvider.autoDispose
    .family<VoiceQuickAddViewModel, VoiceQuickAddState, Object>(
      VoiceQuickAddViewModel.new,
    );

class VoiceQuickAddViewModel extends Notifier<VoiceQuickAddState> {
  VoiceQuickAddViewModel(this.session);
  final Object session;
  late VoiceQuickAddRepository _repository;
  @override
  VoiceQuickAddState build() {
    _repository = ref.watch(voiceQuickAddRepositoryProvider(session));
    void changed() {
      if (ref.mounted) state = _repository.state;
    }

    _repository.addListener(changed);
    ref.onDispose(() => _repository.removeListener(changed));
    return _repository.state;
  }

  void setLocale(String locale) => _repository.locale = locale;
  Future<void> loadSmartMode() =>
      _repository.loadSmartMode().then((result) => result.getOrThrow());
  void setSmartMode(bool value) => _repository.setSmartMode(value);
  Future<void> restoreRecording() =>
      _repository.restoreRecording().then((result) => result.getOrThrow());
  Future<void> start({bool retry = false}) =>
      _repository.start(retry: retry).then((result) => result.getOrThrow());
  Future<void> stop() =>
      _repository.stop().then((result) => result.getOrThrow());
  Future<bool> closeVoice() =>
      _repository.closeVoice().then((result) => result.getOrThrow());
  Future<void> refreshAccess() =>
      _repository.refreshAccess().then((result) => result.getOrThrow());
  Future<void> recoverAccess() =>
      _repository.recoverAccess().then((result) => result.getOrThrow());
  Future<void> useCloudTranscription() =>
      _repository.useCloudTranscription().then((result) => result.getOrThrow());
  Future<void> decomposeTranscript(String transcript) => _repository
      .decomposeTranscript(transcript)
      .then((result) => result.getOrThrow());
  Future<List<String>?> save(
    List<DecomposedTaskDraft> drafts, {
    int? defaultPriority,
    DateTime? defaultDate,
    String? projectId,
    String? kanbanStatusId,
    String? labelId,
  }) async {
    if (!state.canStart || state.saving || drafts.isEmpty) return null;
    _repository.setSaving(true);
    try {
      return await ref.read(saveVoiceDraftsProvider)(
        drafts,
        defaultPriority: defaultPriority,
        defaultDate: defaultDate,
        projectId: projectId,
        kanbanStatusId: kanbanStatusId,
        labelId: labelId,
      );
    } finally {
      if (ref.mounted) _repository.setSaving(false);
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
      ref.watch(billingViewModelProvider).hasActiveEntitlement;
  Future<bool> check() async {
    final keepAlive = ref.keepAlive();
    try {
      var billing = ref.read(billingViewModelProvider);
      if (billing.loading) {
        await ref.read(billingViewModelProvider.notifier).reload();
        if (!ref.mounted) return false;
        billing = ref.read(billingViewModelProvider);
      }
      return billing.hasActiveEntitlement;
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
