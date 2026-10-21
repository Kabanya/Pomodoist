import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';

/// Shared live draft and commit behavior in the main settings and utility panel.
class PomoScaleControl extends ConsumerWidget {
  const PomoScaleControl({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(pomoControllerProvider), l = context.l10n;
    final percent = (c.scale * 100).round();
    final actual = (c.effectiveScale * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(l.pomoSize)),
            Text('$percent%', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        Row(
          children: [
            IconButton(
              tooltip: l.pomoSizeDecrease,
              onPressed: percent <= 25
                  ? null
                  : () => unawaited(
                      c.changeScale(((percent - 5) / 5).round() * .05),
                    ),
              icon: const Icon(LucideIcons.minus, size: 20),
            ),
            Expanded(
              child: Slider(
                min: .25,
                max: 2.5,
                divisions: 45,
                value: c.scale,
                label: '$percent%',
                semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                onChanged: c.previewScale,
                onChangeEnd: (_) => unawaited(c.commitScale()),
              ),
            ),
            IconButton(
              tooltip: l.pomoSizeIncrease,
              onPressed: percent >= 250
                  ? null
                  : () => unawaited(
                      c.changeScale(((percent + 5) / 5).round() * .05),
                    ),
              icon: const Icon(LucideIcons.plus, size: 20),
            ),
          ],
        ),
        if (actual != percent)
          Text(
            l.pomoSizeEffective(actual),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: percent == 100
                ? null
                : () => unawaited(c.changeScale(1)),
            child: Text(l.pomoSizeReset),
          ),
        ),
      ],
    );
  }
}
