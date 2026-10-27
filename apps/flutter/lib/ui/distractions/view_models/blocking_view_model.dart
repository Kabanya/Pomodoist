import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:pomodoist/config/distraction_dependencies.dart';

class BlockingEditorState {
  const BlockingEditorState({
    this.selectedPresetId,
    this.saving = false,
    this.error,
  });
  final String? selectedPresetId, error;
  final bool saving;
}

final blockingViewModelProvider =
    NotifierProvider.autoDispose<BlockingViewModel, BlockingEditorState>(
      BlockingViewModel.new,
    );

class BlockingViewModel extends Notifier<BlockingEditorState> {
  @override
  BlockingEditorState build() => const BlockingEditorState();

  void selectPreset(String id) => state = BlockingEditorState(
    selectedPresetId: id,
    saving: state.saving,
    error: state.error,
  );

  Future<bool> save(Future<void> Function() action) async {
    if (state.saving) return false;
    final keepAlive = ref.keepAlive();
    state = BlockingEditorState(
      selectedPresetId: state.selectedPresetId,
      saving: true,
    );
    try {
      await action();
      if (ref.mounted) {
        state = BlockingEditorState(selectedPresetId: state.selectedPresetId);
      }
      return true;
    } on Object catch (e) {
      if (ref.mounted) {
        state = BlockingEditorState(
          selectedPresetId: state.selectedPresetId,
          error: '$e',
        );
      }
      return false;
    } finally {
      keepAlive.close();
    }
  }

  Future<bool> setProfile(String presetId, String? profileId) => save(() async {
    (await ref
            .read(focusRepositoryProvider)
            .setPresetDistractionProfile(presetId, profileId))
        .getOrThrow();
  });

  Future<bool> updateProfile(String id, Map<String, dynamic> patch) =>
      save(() async {
        final commands = ref.read(distractionRepositoryProvider)!;
        final current = commands.state.profiles.where((p) => p.id == id).first;
        await commands.saveProfile(
          DistractionProfile.fromJson({
            ...current.json,
            ...patch,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      });
}

enum AutomaticCategoryAction { wait, paywall, save }

AutomaticCategoryAction automaticCategoryAction(
  BillingState billing,
  bool enable,
) {
  if (!billing.hasActiveEntitlement &&
      (billing.loading || billing.error != null)) {
    return AutomaticCategoryAction.wait;
  }
  return enable && !billing.hasActiveEntitlement
      ? AutomaticCategoryAction.paywall
      : AutomaticCategoryAction.save;
}
