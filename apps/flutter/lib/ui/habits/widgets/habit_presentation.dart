import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/habits/view_models/habit_presentation_view_model.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The main-area capability is measured before either nested details host reserves space.
class HabitPresentationScope extends InheritedWidget {
  const HabitPresentationScope({
    required this.available,
    required this.presentation,
    required super.child,
    super.key,
  });
  final bool available;
  final HabitPresentation presentation;
  static HabitPresentationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HabitPresentationScope>();
  @override
  bool updateShouldNotify(HabitPresentationScope oldWidget) =>
      available != oldWidget.available ||
      presentation != oldWidget.presentation;
}

class HabitPresentationControl extends ConsumerWidget {
  const HabitPresentationControl({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(habitPresentationProvider);
    final vm = ref.read(habitPresentationProvider.notifier);
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicWidth(
          child: ShadTabs<HabitPresentation>(
            value: state.value,
            gap: 0,
            tabs: [
              for (final value in HabitPresentation.values)
                ShadTab(
                  value: value,
                  height: 44,
                  enabled: !state.loading && !state.saving,
                  child: Text(
                    value == HabitPresentation.rhythm
                        ? l.habitsDayRhythm
                        : l.habitsProgressCircle,
                  ),
                ),
            ],
            onChanged: (value) {
              ref.read(habitsViewModelProvider.notifier).closeOverview();
              vm.select(value);
            },
          ),
        ),
        if (state.error)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                l.habitsPresentationError,
                style: TextStyle(color: context.appColors.error),
              ),
              ShadButton.ghost(onPressed: vm.retry, child: Text(l.commonRetry)),
            ],
          ),
      ],
    );
  }
}
