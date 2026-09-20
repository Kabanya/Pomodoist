part of '../view_models/theme_settings_view_model.dart';

typedef DecodedThemeSettings = ({AppThemeSettings settings, String? legacyRaw});

/// Converts the persisted schema into presentation theme models.
final class ThemeSettingsCodec {
  const ThemeSettingsCodec._();

  static String encode(AppThemeSettings settings) => jsonEncode({
    'version': 2,
    'selectedId': settings.selectedId,
    'customTheme': settings.customTheme.toJson(),
  });

  static DecodedThemeSettings decode(Object? raw) {
    const fallback = AppThemeSettings(isLoaded: true);
    if (raw is! String) return (settings: fallback, legacyRaw: null);
    try {
      final json = jsonDecode(raw);
      if (json is! Map || (json['version'] != 1 && json['version'] != 2)) {
        return (settings: fallback, legacyRaw: null);
      }
      var custom = defaultCustomTheme;
      var selected = json['selectedId'];
      if (json['version'] == 1) {
        final copies = json['customThemes'];
        if (copies is List) {
          for (final record in copies) {
            if (record is! Map || record['id'] != selected) continue;
            try {
              custom = AppThemeDefinition.fromJson(record);
              selected = 'custom';
              break;
            } on FormatException {
              continue;
            }
          }
        }
      } else {
        try {
          custom = AppThemeDefinition.fromJson(json['customTheme']);
        } on FormatException {
          // A damaged Custom record does not make built-in themes unusable.
        }
      }
      final validSelection =
          selected is String &&
          (selected == 'custom' ||
              builtinAppThemes.any((theme) => theme.id == selected));
      return (
        settings: AppThemeSettings(
          isLoaded: true,
          customTheme: custom,
          selectedId: validSelection ? selected : 'classic',
        ),
        legacyRaw: json['version'] == 1 ? raw : null,
      );
    } on FormatException {
      return (settings: fallback, legacyRaw: null);
    }
  }
}
