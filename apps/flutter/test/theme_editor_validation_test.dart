import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/features/settings/presentation/theme_settings_card.dart';

void main() {
  test('saving rejects invalid colors in either palette', () {
    expect(themeEditorCanSave(['#FFFFFF', '123456']), isTrue);
    expect(themeEditorCanSave(['#FFFFFF', '#12345Z']), isFalse);
    expect(themeEditorCanSave(['#80112233']), isFalse);
  });

  test('contrast feedback includes text on custom button and error fills', () {
    final palette = AppTheme.classicLight;
    expect(themeHasLowContrast(palette), isFalse);
    expect(
      themeHasLowContrast(palette.copyWith(primaryText: palette.canvas)),
      isTrue,
    );
    expect(
      themeHasLowContrast(palette.copyWith(onAccent: palette.accentFill)),
      isTrue,
    );
    expect(
      themeHasLowContrast(palette.copyWith(onError: palette.error)),
      isTrue,
    );
    expect(
      themeHasLowContrast(
        palette.copyWith(accentFill: Colors.black, onAccent: Colors.white),
      ),
      isFalse,
    );
  });
}
