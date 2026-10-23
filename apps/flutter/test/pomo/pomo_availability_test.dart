import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_preferences_repository_impl.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'pomo_controller_test.dart' as fixtures;
import 'pomo_environment_repository_test.dart' as environment_fixtures;
import 'package:pomodoist/data/repositories/pomo/pomo_environment_repository_impl.dart';

void main() {
  test(
    'explicit focus-only intent survives a bridge outage and disabling cancels recovery',
    () async {
      final preferences = LocalPomoPreferencesRepository(
        fixtures.MemoryPreferences(),
      );
      await preferences.load();
      await preferences.update((p) => p.copyWith(focusOnly: true));
      final host = fixtures.Host();
      final controller = PomoController(preferences, host);
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);
      await controller.initialize();
      await controller.restore();
      expect(controller.visible, true);
      await controller.setHostAvailable(false);
      expect(preferences.state.dismissed, false);
      await controller.setHostAvailable(true);
      expect(host.shows, 2);
      await controller.setHostAvailable(false);
      await controller.setEnabled(false);
      await controller.setHostAvailable(true);
      expect(host.shows, 2);
      expect(controller.visible, false);
    },
  );

  test(
    'extension commands share busy deduplication and retain actionable failures',
    () async {
      final preferences = LocalPomoPreferencesRepository(
        fixtures.MemoryPreferences(),
      );
      final controller = PomoController(
        preferences,
        fixtures.Host(),
        hostAvailable: false,
      );
      final native = environment_fixtures.Native()
        ..failAction = true
        ..actionGate = Completer<void>();
      final repository = LinuxPomoEnvironmentRepository(
        native: native,
        followTransport: environment_fixtures.Transport(),
      );
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);
      addTearDown(repository.dispose);
      await controller.initialize();
      final pending = controller.command(repository.installGnomeExtension);
      expect(controller.busy, true);
      await controller.command(repository.installGnomeExtension);
      await Future<void>.delayed(Duration.zero);
      expect(native.actions, ['install']);
      native.actionGate!.complete();
      await pending;
      expect(controller.busy, false);
      expect(controller.error, isA<StateError>());
      expect(preferences.state.enabled, false);
      native.failAction = false;
      await controller.command(repository.gnomeExtensionStatus);
      expect(controller.error, isNull);
      expect(native.actions, ['install', 'status']);
    },
  );

  test(
    'unavailable desktop preserves opt-in and restores after reconnection',
    () async {
      final preferences = LocalPomoPreferencesRepository(
        fixtures.MemoryPreferences(),
      );
      await preferences.load();
      await preferences.update((p) => p.copyWith(enabled: true));
      final host = fixtures.Host();
      final controller = PomoController(
        preferences,
        host,
        hostAvailable: false,
      );
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);
      await controller.initialize();
      expect(host.shows, 0);
      expect(controller.visible, false);
      await controller.setHostAvailable(true);
      expect(host.shows, 1);
      await controller.openSettings();
      expect(host.panel, true);
      await controller.setHostAvailable(false);
      expect(controller.visible, false);
      expect(host.panel, false);
      expect(preferences.state.enabled, true);
      await controller.setHostAvailable(true);
      expect(host.shows, 2);
      expect(controller.visible, true);
      await controller.setHostAvailable(true);
      expect(host.shows, 2);
    },
  );
}
