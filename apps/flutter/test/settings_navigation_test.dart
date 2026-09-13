import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/settings/presentation/settings_navigation.dart';

void main() {
  test('section URLs round-trip and ignore unrelated parameters', () {
    for (final section in SettingsSection.values) {
      final location = settingsLocation(section);
      expect(location.path, '/settings');
      expect(settingsSectionFromUri(location), section);
      expect(settingsSectionFromUri(Uri.parse('$location&task=123')), section);
    }
    expect(settingsLocation(null).toString(), '/settings');
  });

  test('missing, unknown, empty and ambiguous sections have no selection', () {
    for (final query in [
      '',
      '?section=',
      '?section=unknown',
      '?section=account&section=general',
    ]) {
      expect(settingsSectionFromUri(Uri.parse('/settings$query')), isNull);
    }
  });

  test(
    'initial defaults depend on layout, but resizing retains the destination',
    () {
      for (final query in ['', '?section=unknown']) {
        final wide = SettingsNavigation(Uri.parse('/settings$query'));
        wide.resolveLayout(wide: true);
        expect(wide.selected, SettingsSection.general);
        wide.resolveLayout(wide: false);
        expect(wide.selected, SettingsSection.general);

        final narrow = SettingsNavigation(Uri.parse('/settings$query'));
        narrow.resolveLayout(wide: false);
        expect(narrow.selected, isNull);
        narrow.resolveLayout(wide: true);
        expect(narrow.selected, SettingsSection.general);
      }
    },
  );

  test(
    'explicit links win on either layout and URL navigation resets defaults',
    () {
      final navigation = SettingsNavigation(
        settingsLocation(SettingsSection.account),
      );
      navigation.resolveLayout(wide: false);
      expect(navigation.selected, SettingsSection.account);
      navigation.resolveLayout(wide: true);
      expect(navigation.selected, SettingsSection.account);
      navigation.syncLocation(settingsLocation(SettingsSection.appearance));
      navigation.resolveLayout(wide: true);
      expect(navigation.selected, SettingsSection.appearance);
      navigation.syncLocation(settingsLocation(null));
      navigation.resolveLayout(wide: false);
      expect(navigation.selected, isNull);
      navigation.syncLocation(settingsLocation(null));
      navigation.resolveLayout(wide: true);
      expect(navigation.selected, SettingsSection.general);
    },
  );
}
