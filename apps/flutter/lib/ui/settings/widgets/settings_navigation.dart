enum SettingsSection {
  general,
  appearance,
  tasksFocus,
  pomo,
  integrations,
  account,
  about,
}

String settingsSectionValue(SettingsSection section) =>
    section == SettingsSection.tasksFocus ? 'tasks-focus' : section.name;

SettingsSection? settingsSectionFromUri(Uri uri) {
  final values = uri.queryParametersAll['section'];
  if (values == null || values.length != 1) return null;
  for (final section in SettingsSection.values) {
    if (settingsSectionValue(section) == values.single) return section;
  }
  return null;
}

Uri settingsLocation(SettingsSection? section) => Uri(
  path: '/settings',
  queryParameters: section == null
      ? null
      : {'section': settingsSectionValue(section)},
);

/// Resizing preserves a selection; the wide layout needs a content section.
class SettingsNavigation {
  SettingsNavigation(this.location)
    : selected = settingsSectionFromUri(location);

  Uri location;
  SettingsSection? selected;
  List<SettingsSection> _sections = SettingsSection.values;

  List<SettingsSection> get sections => _sections;

  int get contentIndex =>
      selected == null ? 0 : _sections.indexOf(selected!) + 1;

  void syncLocation(Uri value) {
    if (value == location) return;
    location = value;
    selected = settingsSectionFromUri(value);
  }

  void resolveLayout({required bool wide, bool pomoAvailable = true}) {
    _sections = pomoAvailable
        ? SettingsSection.values
        : List.unmodifiable(
            SettingsSection.values.where(
              (section) => section != SettingsSection.pomo,
            ),
          );
    if (!_sections.contains(selected)) selected = null;
    selected ??= wide ? SettingsSection.general : null;
  }
}
