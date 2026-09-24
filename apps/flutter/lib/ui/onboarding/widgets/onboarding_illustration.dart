import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/onboarding/view_models/onboarding_view_model.dart';

/// Decorative slide artwork; the controls below expose the actual settings.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({
    required this.step,
    required this.timerStyle,
    super.key,
  });

  final OnboardingStep step;
  final FocusTimerVisualStyle timerStyle;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: SizedBox(
          height: 148,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 280,
                height: 148,
                child: switch (step) {
                  OnboardingStep.language => const _LanguageArtwork(),
                  OnboardingStep.timer => Center(
                    child: OnboardingTimerPreview(
                      style: timerStyle,
                      large: true,
                    ),
                  ),
                  OnboardingStep.paywall => const _ProArtwork(),
                  OnboardingStep.account => const _DevicesArtwork(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingTimerPreview extends StatelessWidget {
  const OnboardingTimerPreview({
    required this.style,
    this.large = false,
    super.key,
  });

  final FocusTimerVisualStyle style;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final time = Text(
      '25:00',
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
      style: AppTheme.monoTextStyle.copyWith(
        fontSize: large ? 32 : 24,
        fontWeight: FontWeight.w400,
        color: colors.primaryText,
        letterSpacing: -1,
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: large ? 200 : 120,
        height: large ? 136 : 104,
        child: style == FocusTimerVisualStyle.circle
            ? Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: large ? 128 : 96,
                    child: CircularProgressIndicator(
                      value: 0.75,
                      strokeWidth: large ? 5 : 3,
                      color: colors.accent,
                      backgroundColor: colors.border,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  time,
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  time,
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: 0.75,
                    minHeight: large ? 5 : 3,
                    borderRadius: BorderRadius.circular(4),
                    color: colors.accent,
                    backgroundColor: colors.border,
                  ),
                ],
              ),
      ),
    );
  }
}

class _LanguageArtwork extends StatelessWidget {
  const _LanguageArtwork();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final glyph = switch (Localizations.localeOf(context).languageCode) {
      'ru' => 'Я',
      'de' => 'Ä',
      'es' => 'Ñ',
      'fr' => 'É',
      'ar' => 'ع',
      'zh' => '文',
      'pt' => 'ã',
      'ja' => 'あ',
      'ko' => '한',
      _ => 'A',
    };
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: colors.accentTint,
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 116,
          height: 116,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentFill,
            shape: BoxShape.circle,
          ),
          child: Text(
            glyph,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              color: colors.onAccent,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const Positioned(
          left: 20,
          top: 8,
          child: _LanguageChip(text: 'Hello', angle: -0.12),
        ),
        const Positioned(
          right: 10,
          bottom: 12,
          child: _LanguageChip(text: 'Привет', angle: 0.12),
        ),
        const Positioned(
          left: 8,
          bottom: 18,
          child: _LanguageChip(text: 'こんにちは', angle: -0.16),
        ),
      ],
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.text, required this.angle});
  final String text;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        border: Border.all(color: context.appColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}

class _ProArtwork extends StatelessWidget {
  const _ProArtwork();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.rotate(
          angle: -0.32,
          child: Container(
            width: 176,
            height: 96,
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(80),
            ),
          ),
        ),
        Text(
          'Pro',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: -3,
          ),
        ),
        Positioned(
          right: 55,
          top: 10,
          child: Icon(LucideIcons.plus, color: colors.accent, size: 28),
        ),
        Positioned(
          bottom: 0,
          child: Row(
            children: [
              for (final height in [
                8.0,
                16.0,
                24.0,
                12.0,
                28.0,
                18.0,
                24.0,
                12.0,
                8.0,
              ])
                Container(
                  width: 3,
                  height: height,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DevicesArtwork extends StatelessWidget {
  const _DevicesArtwork();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(left: 42, top: 12, child: _device(context, 164, 108)),
        Positioned(
          left: 34,
          top: 124,
          child: Container(
            width: 180,
            height: 5,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        Positioned(right: 26, bottom: 6, child: _device(context, 56, 104)),
        Positioned(
          left: 101,
          top: 52,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.accentFill,
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 4),
            ),
            child: Icon(LucideIcons.check, color: colors.onAccent, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _device(BuildContext context, double width, double height) =>
      Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        decoration: BoxDecoration(
          color: context.appColors.surfaceTint,
          border: Border.all(color: context.appColors.border, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final factor in [0.8, 0.6, 0.7])
              FractionallySizedBox(
                widthFactor: factor,
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: factor == 0.6
                        ? context.appColors.accent
                        : context.appColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
      );
}
