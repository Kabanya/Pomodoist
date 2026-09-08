import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/task_time.dart';
import 'package:pomodoist/app/theme/app_theme.dart';

void main() {
  test(
    'Material and Shadcn share semantic colors during theme interpolation',
    () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();
      for (final theme in [light, ThemeData.lerp(light, dark, .5), dark]) {
        final colors = theme.extension<AppThemePalette>()!;
        final shad = AppTheme.shadFromMaterial(theme);
        expect(shad.brightness, theme.brightness);
        expect(shad.colorScheme.background, colors.canvas);
        expect(shad.colorScheme.foreground, colors.primaryText);
        expect(shad.colorScheme.card, colors.surface);
        expect(shad.colorScheme.popover, colors.surface);
        expect(shad.colorScheme.primary, theme.colorScheme.primary);
        expect(shad.colorScheme.primaryForeground, theme.colorScheme.onPrimary);
        expect(shad.colorScheme.ring, colors.accent);
        expect(shad.colorScheme.selection, colors.accentTint);
        expect(
          shad.textTheme.p.fontFamily,
          theme.textTheme.bodyLarge!.fontFamily,
        );
        expect(shad.textTheme.p.fontSize, theme.textTheme.bodyLarge!.fontSize);
        expect(
          shad.textTheme.h2.fontSize,
          theme.textTheme.headlineMedium!.fontSize,
        );
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
      expect(colors.taskTimeColor(TaskTimeState.overdue), colors.accent);
      expect(colors.taskTimeColor(TaskTimeState.completed), colors.mutedText);
    }
  });
}
