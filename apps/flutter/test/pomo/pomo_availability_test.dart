import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_preferences_repository_impl.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'pomo_controller_test.dart' as fixtures;

void main() {
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
