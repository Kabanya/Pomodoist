import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch, ShadContextMenuItem;

import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_environment_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

import 'pomo_linux_settings.dart';
import 'pomo_scale_control.dart';

class PomoSettings extends ConsumerWidget {
  const PomoSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLinux = !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
    if (!isLinux && !pomoSupported) return const SizedBox.shrink();
    final environment = isLinux
        ? ref.watch(pomoEnvironmentStateProvider).value ??
              const PomoEnvironment()
        : null;
    final available =
        environment == null || (!environment.checking && environment.available);
    final c = ref.watch(pomoControllerProvider), p = c.prefs;
    final l = context.l10n;
    Widget row(
      String title,
      bool value,
      Future<void> Function(bool) update, {
      String? subtitle,
      bool active = true,
    }) => SettingsRow(
      title: title,
      subtitle: subtitle,
      controlWidth: 48,
      control: ShadSwitch(
        value: value,
        enabled: active,
        onChanged: (v) => unawaited(update(v)),
      ),
    );
    return SettingsGroup(
      children: [
        row(
          l.pomoTitle,
          p.enabled,
          c.setEnabled,
          subtitle: l.pomoDescription,
          active: available,
        ),
        if (environment != null && !available)
          PomoLinuxAvailability(environment: environment),
        if (available) ...[
          if (environment != null)
            PomoLinuxDisplaySettings(environment: environment),
          const Padding(padding: EdgeInsets.all(16), child: PomoScaleControl()),
          const PomoTimerControl(),
          if (p.enabled) ...[
            row(
              l.pomoFocusOnly,
              p.focusOnly,
              (v) => c.updatePreferences((p) => p.copyWith(focusOnly: v)),
            ),
            row(
              l.pomoQuiet,
              p.quiet,
              (v) => c.updatePreferences((p) => p.copyWith(quiet: v)),
              subtitle: l.pomoQuietDescription,
            ),
            row(
              l.pomoReduceMotion,
              p.reduceMotion,
              (v) => c.updatePreferences((p) => p.copyWith(reduceMotion: v)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: c.closing
                        ? null
                        : () => unawaited(
                            c.visible ? c.hideManually() : c.restore(),
                          ),
                    child: Text(c.visible ? l.pomoHide : l.pomoShow),
                  ),
                  TextButton(
                    onPressed: () => unawaited(c.resetPosition()),
                    child: Text(l.pomoResetPosition),
                  ),
                ],
              ),
            ),
          ],
        ],
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l.pomoError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class PomoTimerControl extends ConsumerWidget {
  const PomoTimerControl({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(pomoControllerProvider);
    final label = context.l10n.pomoShowTimer;
    return SettingsRow(
      title: label,
      controlWidth: 48,
      control: Semantics(
        label: label,
        child: ShadSwitch(
          value: c.prefs.showTimer,
          onChanged: (value) => unawaited(
            c.updatePreferences((p) => p.copyWith(showTimer: value)),
          ),
        ),
      ),
    );
  }
}

class PomoMenuItem extends ConsumerWidget {
  const PomoMenuItem({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(pomoControllerProvider);
    return ShadContextMenuItem(
      height: 44,
      enabled: !c.closing,
      onPressed: () => unawaited(c.visible ? c.hideManually() : c.restore()),
      child: Text(c.visible ? context.l10n.pomoHide : context.l10n.pomoShow),
    );
  }
}
