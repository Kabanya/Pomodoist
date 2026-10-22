import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/settings/widgets/settings_navigation.dart';

void main() {
  test('Pomo deep links retain their destination across layout changes', () {
    final navigation = SettingsNavigation(Uri.parse('/settings?section=pomo'));
    navigation.resolveLayout(wide: false);
    expect(navigation.selected?.name, 'pomo');
    navigation.resolveLayout(wide: true);
    expect(navigation.selected?.name, 'pomo');
    navigation.resolveLayout(wide: false);
    expect(navigation.selected?.name, 'pomo');
  });

  test(
    'unavailable Pomo links use the initial destination for each layout',
    () {
      for (final wide in [false, true]) {
        final navigation = SettingsNavigation(
          Uri.parse('/settings?section=pomo'),
        );
        navigation.resolveLayout(wide: wide, pomoAvailable: false);
        expect(
          navigation.sections.map((section) => section.name),
          isNot(contains('pomo')),
        );
        expect(navigation.selected, wide ? SettingsSection.general : isNull);
        expect(navigation.contentIndex, wide ? 1 : 0);
      }
    },
  );

  test(
    'filtered sections keep later destinations aligned with their content',
    () {
      final navigation = SettingsNavigation(
        Uri.parse('/settings?section=account'),
      );
      navigation.resolveLayout(wide: true, pomoAvailable: false);
      expect(navigation.selected, SettingsSection.account);
      expect(navigation.contentIndex, 5);
      navigation.resolveLayout(wide: false, pomoAvailable: false);
      expect(navigation.selected, SettingsSection.account);
      expect(navigation.contentIndex, 5);

      navigation.syncLocation(Uri.parse('/settings?section=integrations'));
      navigation.resolveLayout(wide: false, pomoAvailable: false);
      expect(navigation.selected, SettingsSection.integrations);
      expect(navigation.contentIndex, 4);

      navigation.syncLocation(Uri.parse('/settings?section=about'));
      navigation.resolveLayout(wide: true, pomoAvailable: false);
      expect(navigation.selected, SettingsSection.about);
      expect(navigation.contentIndex, 6);
    },
  );

  test('Pomo is selectable when available and falls back when unavailable', () {
    final navigation = SettingsNavigation(Uri.parse('/settings?section=pomo'));
    navigation.resolveLayout(wide: true, pomoAvailable: true);
    expect(
      navigation.sections.map((section) => section.name),
      contains('pomo'),
    );
    expect(navigation.selected?.name, 'pomo');
    expect(navigation.contentIndex, 4);

    navigation.resolveLayout(wide: false, pomoAvailable: false);
    expect(navigation.selected, isNull);
    expect(navigation.contentIndex, 0);
    navigation.resolveLayout(wide: true, pomoAvailable: false);
    expect(navigation.selected, SettingsSection.general);
  });

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
