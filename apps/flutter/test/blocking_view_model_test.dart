import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/ui/distractions/view_models/blocking_view_model.dart';
import '../testing/fakes/fake_focus_repository.dart';

void main() {
  test('automatic categories distinguish Free, Pro and unverified access', () {
    expect(
      automaticCategoryAction(BillingState(), true),
      AutomaticCategoryAction.wait,
    );
    expect(
      automaticCategoryAction(
        BillingState(loading: false, error: 'offline'),
        true,
      ),
      AutomaticCategoryAction.wait,
    );
    expect(
      automaticCategoryAction(BillingState(loading: false), true),
      AutomaticCategoryAction.paywall,
    );
    expect(
      automaticCategoryAction(BillingState(loading: false), false),
      AutomaticCategoryAction.save,
    );
    expect(
      automaticCategoryAction(
        BillingState(accountEntitlementActive: true),
        true,
      ),
      AutomaticCategoryAction.save,
    );
  });

  test('browsing presets never changes the running or remembered Focus', () {
    final focus = FakeFocusRepository();
    final container = ProviderContainer(
      overrides: [focusRepositoryProvider.overrideWithValue(focus)],
    );
    addTearDown(container.dispose);
    final listener = container.listen(blockingViewModelProvider, (_, _) {});
    addTearDown(listener.close);
    container.read(blockingViewModelProvider.notifier).selectPreset('other');
    expect(container.read(blockingViewModelProvider).selectedPresetId, 'other');
    expect(focus.startRunCalls, isEmpty);
    expect(focus.changeActiveRunPresetCalls, isEmpty);
  });

  test(
    'pending save remains shared when the desk is reopened before completion',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final listener = container.listen(blockingViewModelProvider, (_, _) {});
      final write = Completer<void>();
      final pending = container
          .read(blockingViewModelProvider.notifier)
          .save(() => write.future);
      listener.close();
      await container.pump();
      final reopened = container.listen(blockingViewModelProvider, (_, _) {});
      addTearDown(reopened.close);
      expect(container.read(blockingViewModelProvider).saving, true);
      expect(
        await container
            .read(blockingViewModelProvider.notifier)
            .save(() async => fail('must not overwrite an in-flight profile')),
        false,
      );
      write.complete();
      expect(await pending, true);
      expect(container.read(blockingViewModelProvider).saving, false);
    },
  );

  test(
    'save is pending until completion, exposes failure and permits retry',
    () async {
      final focus = FakeFocusRepository();
      final container = ProviderContainer(
        overrides: [focusRepositoryProvider.overrideWithValue(focus)],
      );
      addTearDown(container.dispose);
      final listener = container.listen(blockingViewModelProvider, (_, _) {});
      addTearDown(listener.close);
      final vm = container.read(blockingViewModelProvider.notifier);
      final write = Completer<void>();
      final saving = vm.save(() => write.future);
      expect(container.read(blockingViewModelProvider).saving, true);
      expect(await vm.save(() async => fail('duplicate save')), false);
      write.completeError(StateError('disk full'));
      expect(await saving, false);
      expect(container.read(blockingViewModelProvider).saving, false);
      expect(
        container.read(blockingViewModelProvider).error,
        contains('disk full'),
      );
      expect(await vm.setProfile('classic', null), true);
      expect(focus.setPresetDistractionProfileCalls.single, (
        presetId: 'classic',
        profileId: null,
      ));
      expect(container.read(blockingViewModelProvider).error, isNull);
      focus.setPresetDistractionProfileError = StateError('outbox failure');
      expect(await vm.setProfile('classic', 'work'), false);
      expect(
        container.read(blockingViewModelProvider).error,
        contains('outbox failure'),
      );
    },
  );
}
