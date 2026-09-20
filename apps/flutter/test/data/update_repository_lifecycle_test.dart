import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/update_dependencies.dart';
import 'package:pomodoist/data/repositories/updates/update_repository.dart';
import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/ui/updates/view_models/update_view_model.dart';

import '../desktop_update_controller_test.dart' as support;

void main() {
  test(
    'repeated checks refresh the offer without reloading preferences',
    () async {
      final source = support.FakeUpdateSource();
      final preferences = support.MemoryUpdatePreferences();
      final repository = support.testController(
        source: source,
        preferences: preferences,
      );
      addTearDown(repository.dispose);

      expect(await repository.check(), isNot(UpdateCheckOutcome.skipped));
      expect(source.calls, 1);
      expect(repository.state.phase, UpdatePhase.available);
      expect(repository.state.offer!.tag, 'v1.1.0');

      source.offer = support.testOffer('v1.2.0');
      expect(await repository.check(), isNot(UpdateCheckOutcome.skipped));
      expect(source.calls, 2);
      expect(repository.state.offer!.tag, 'v1.2.0');
      expect(preferences.seen, {'v1.1.0', 'v1.2.0'});
    },
  );

  test(
    'dismissing the popup during a download keeps install progress',
    () async {
      final installer = support.FakeUpdateInstaller()..gate = Completer<void>();
      final repository = support.testController(installer: installer);
      final container = ProviderContainer(
        overrides: [updateRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      addTearDown(repository.dispose);
      container.listen(updateViewModelProvider, (_, _) {});
      final view = container.read(updateViewModelProvider.notifier);

      await view.check();
      expect(container.read(updateViewModelProvider).popupVisible, isTrue);

      final updating = view.update();
      await pumpEventQueue();
      expect(repository.state.phase, UpdatePhase.downloading);

      view.dismiss();
      expect(container.read(updateViewModelProvider).popupVisible, isFalse);
      expect(repository.state.phase, UpdatePhase.downloading);

      installer.gate!.complete();
      await updating;
      expect(installer.installs, 1);
      expect(repository.state.phase, UpdatePhase.installing);
    },
  );

  test('disposal during a source response publishes no late state', () async {
    final source = support.FakeUpdateSource()..gate = Completer<void>();
    final repository = support.testController(source: source);
    final states = <Object>[];
    final subscription = repository.watchState().listen(states.add);

    final checking = repository.check();
    await pumpEventQueue();
    expect(source.calls, 1);

    repository.dispose();
    source.gate!.complete();
    expect(await checking, UpdateCheckOutcome.skipped);

    await pumpEventQueue();
    final delivered = states.length;
    await Future<void>.delayed(Duration.zero);
    expect(states.length, delivered);
    await subscription.cancel();
    expect(repository.state.phase, UpdatePhase.checking);
  });

  test('install failure keeps the offer and retry installs once', () async {
    final installer = support.FakeUpdateInstaller()..fail = true;
    final repository = support.testController(installer: installer);
    addTearDown(repository.dispose);

    await repository.check();
    await repository.update();
    expect(repository.state.phase, UpdatePhase.failed);
    expect(repository.state.error, contains('Checksum'));
    expect(repository.state.offer, isNotNull);

    installer.fail = false;
    await repository.update();
    expect(installer.installs, 2);
    expect(repository.state.phase, UpdatePhase.installing);
  });
}
