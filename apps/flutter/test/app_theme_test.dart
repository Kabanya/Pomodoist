import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/task_time.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/app/theme/app_theme_settings.dart';

void main() {
  test(
    'Sepia and Graphite retain readable button text and independent status colors',
    () {
      for (final id in ['sepia', 'graphite']) {
        final preset = builtinAppThemes.firstWhere((theme) => theme.id == id);
        for (final (palette, classic) in [
          (preset.light, AppTheme.classicLight),
          (preset.dark, AppTheme.classicDark),
        ]) {
          expect(
            themeContrastRatio(palette.accentFill, palette.onAccent),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            themeContrastRatio(palette.canvas, palette.primaryText),
            greaterThanOrEqualTo(4.5),
          );
          expect(palette.error, classic.error);
          expect(palette.overdue, classic.overdue);
          expect(palette.warning, classic.warning);
          expect(palette.info, classic.info);
          expect(palette.success, classic.success);
          expect(
            AppThemePalette.fromJson(palette.toJson()).toJson(),
            palette.toJson(),
          );
        }
      }
      final graphite = builtinAppThemes
          .firstWhere((theme) => theme.id == 'graphite')
          .dark;
      final material = AppTheme.dark(palette: graphite);
      expect(material.colorScheme.onPrimary.computeLuminance(), lessThan(.1));
      expect(
        AppTheme.shadFromMaterial(material).colorScheme.primaryForeground,
        graphite.onAccent,
      );
    },
  );

  test(
    'editable colors round-trip, reject malformed colors, and preserve semantic roles',
    () {
      final palette = AppTheme.light().extension<AppThemePalette>()!;
      final edited = palette
          .withColor(AppThemeColor.accent, const Color(0xFF123456))
          .withColor(AppThemeColor.onAccent, const Color(0xFF101010))
          .withColor(AppThemeColor.error, const Color(0xFFAA1122))
          .withColor(AppThemeColor.onError, const Color(0xFFEEDDCC));
      final restored = AppThemePalette.fromJson(edited.toJson());
      expect(restored.accent, const Color(0xFF123456));
      expect(restored.taskTimeColor(TaskTimeState.overdue), palette.overdue);
      final material = AppTheme.light(palette: restored);
      final shad = AppTheme.shadFromMaterial(material);
      expect(material.colorScheme.error, const Color(0xFFAA1122));
      expect(shad.colorScheme.destructiveForeground, const Color(0xFFEEDDCC));
      expect(material.colorScheme.onPrimary, const Color(0xFF101010));
      expect(shad.colorScheme.primaryForeground, const Color(0xFF101010));
      expect(
        () =>
            AppThemePalette.fromJson({...edited.toJson(), 'canvas': '#12345Z'}),
        throwsFormatException,
      );
      expect(() => AppThemePalette.fromJson({}), throwsFormatException);
      expect(parseThemeColor('#80112233'), isNull);
      expect(parseThemeColor(' aAbBcC '), const Color(0xFFAABBCC));
      expect(themeContrastRatio(Colors.black, Colors.white), closeTo(21, .001));
      expect(themeContrastRatio(Colors.white, Colors.white), 1);
    },
  );

  test(
    'Material and Shadcn share semantic colors during theme interpolation',
    () {
      for (final preset in builtinAppThemes) {
        final light = AppTheme.light(palette: preset.light);
        final dark = AppTheme.dark(
          palette: preset.dark.copyWith(
            onAccent: Colors.black,
            onError: Colors.black,
          ),
        );
        for (final theme in [light, ThemeData.lerp(light, dark, .5), dark]) {
          final colors = theme.extension<AppThemePalette>()!;
          final shad = AppTheme.shadFromMaterial(theme);
          expect(shad.brightness, theme.brightness);
          expect(shad.colorScheme.background, colors.canvas);
          expect(shad.colorScheme.foreground, colors.primaryText);
          expect(shad.colorScheme.card, colors.surface);
          expect(shad.colorScheme.popover, colors.surface);
          expect(shad.colorScheme.primary, theme.colorScheme.primary);
          expect(
            shad.colorScheme.primaryForeground,
            theme.colorScheme.onPrimary,
          );
          expect(shad.colorScheme.ring, colors.accent);
          expect(shad.colorScheme.selection, colors.accentTint);
          expect(shad.colorScheme.destructive, colors.error);
          expect(shad.colorScheme.destructiveForeground, colors.onError);
          expect(
            shad.textTheme.p.fontFamily,
            theme.textTheme.bodyLarge!.fontFamily,
          );
          expect(
            shad.textTheme.p.fontSize,
            theme.textTheme.bodyLarge!.fontSize,
          );
          expect(
            shad.textTheme.h2.fontSize,
            theme.textTheme.headlineMedium!.fontSize,
          );
        }
      }
    },
  );

  test(
    'new semantic roles interpolate instead of jumping during live edits',
    () {
      final first = AppTheme.classicLight.copyWith(
        error: Colors.black,
        overdue: Colors.black,
        onAccent: Colors.black,
        onError: Colors.black,
      );
      final second = first.copyWith(
        error: Colors.white,
        overdue: Colors.white,
        onAccent: Colors.white,
        onError: Colors.white,
      );
      final middle = first.lerp(second, .5);
      for (final color in [
        middle.error,
        middle.overdue,
        middle.onAccent,
        middle.onError,
      ]) {
        expect(color.computeLuminance(), inExclusiveRange(0, 1));
      }
    },
  );

  test(
    'Reduce Motion removes overlay durations without changing theme colors',
    () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final normal = AppTheme.shadFromMaterial(theme);
        final reduced = AppTheme.shadFromMaterial(theme, reduceMotion: true);
        expect(reduced.colorScheme, normal.colorScheme);
        for (final effects in [
          reduced.primaryDialogTheme.animateIn!,
          reduced.primaryDialogTheme.animateOut!,
          reduced.alertDialogTheme.animateIn!,
          reduced.popoverTheme.effects!,
          reduced.contextMenuTheme.effects!,
          reduced.tooltipTheme.effects!,
          reduced.sheetTheme.animateIn!,
          reduced.sheetTheme.animateOut!,
        ]) {
          expect(effects, isNotEmpty);
          expect(
            effects.every((effect) => effect.duration == Duration.zero),
            isTrue,
          );
        }
        expect(reduced.popoverTheme.reverseDuration, Duration.zero);
        expect(reduced.sheetTheme.snapAnimationDuration, Duration.zero);
        expect(
          normal.primaryDialogTheme.animateIn!.first.duration!.inMilliseconds,
          greaterThan(0),
        );
      }
    },
  );

  test('task status colors keep their semantic roles in both palettes', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final colors = theme.extension<AppThemePalette>()!;
      expect(colors.taskTimeColor(TaskTimeState.focused), colors.success);
      expect(colors.taskTimeColor(TaskTimeState.future), colors.info);
      expect(colors.taskTimeColor(TaskTimeState.current), colors.warning);
      expect(colors.taskTimeColor(TaskTimeState.overdue), colors.overdue);
      expect(colors.taskTimeColor(TaskTimeState.completed), colors.mutedText);
    }
  });
}
