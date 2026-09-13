enum SettingsSection {
  general,
  appearance,
  tasksFocus,
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

  void syncLocation(Uri value) {
    if (value == location) return;
    location = value;
    selected = settingsSectionFromUri(value);
  }

  void resolveLayout({required bool wide}) {
    selected ??= wide ? SettingsSection.general : null;
  }
}
