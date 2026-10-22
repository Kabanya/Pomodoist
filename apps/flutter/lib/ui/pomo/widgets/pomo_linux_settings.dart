import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadOption, ShadRadio, ShadRadioGroup, ShadSelect, ShadSwitch;

import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/platform/legal_urls.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_environment_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

class PomoLinuxAvailability extends ConsumerWidget {
  const PomoLinuxAvailability({required this.environment, super.key});

  final PomoEnvironment environment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final version = ref.watch(pomoAppVersionProvider).value ?? 'unknown';
    if (environment.checking) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l.pomoLinuxChecking)),
          ],
        ),
      );
    }
    final description = [
      environment.distribution,
      environment.desktop,
      environment.sessionType,
    ].where((value) => value.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.pomoLinuxUnavailable(
              description.isEmpty ? l.pomoLinuxUnknownEnvironment : description,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => unawaited(_write(context, version)),
                child: Text(l.pomoLinuxWrite),
              ),
              TextButton(
                onPressed: () => unawaited(_copy(context, version)),
                child: Text(l.pomoLinuxCopyDetails),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _write(BuildContext context, String version) async {
    var opened = false;
    try {
      opened = await launchPomodoistExternalUrl(
        buildPomoSupportUri(environment, version).toString(),
      );
    } catch (_) {
      // The copy action remains available when there is no mail application.
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.pomoLinuxMailError)));
    }
  }

  Future<void> _copy(BuildContext context, String version) async {
    await Clipboard.setData(
      ClipboardData(text: buildPomoSupportDetails(environment, version)),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.pomoLinuxCopied)));
    }
  }
}

class PomoLinuxDisplaySettings extends ConsumerWidget {
  const PomoLinuxDisplaySettings({required this.environment, super.key});

  final PomoEnvironment environment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(pomoControllerProvider);
    final prefs = c.prefs;
    final l = context.l10n;
    final pinned = prefs.displayMode == PomoDisplayMode.pinned;
    final names = {
      for (final display in environment.displays) display.id: display.name,
    };
    final selectedId = prefs.pinnedDisplayId;
    String monitorLabel(String id) =>
        names[id] ?? l.pomoLinuxMonitorUnavailable(id);
    return SettingsGroup(
      children: [
        SettingsRow(
          title: l.pomoLinuxDisplayMode,
          subtitle: !environment.canFollow
              ? l.pomoLinuxFollowUnavailable
              : environment.followSource == PomoFollowSource.workspace
              ? l.pomoLinuxWorkspaceFollow
              : null,
          control: ShadRadioGroup<PomoDisplayMode>(
            key: ValueKey(prefs.displayMode),
            initialValue: prefs.displayMode,
            items: [
              ShadRadio(
                value: PomoDisplayMode.followUser,
                enabled: environment.canFollow,
                padding: const EdgeInsets.symmetric(vertical: 12),
                label: Text(l.pomoLinuxFollowUser),
              ),
              ShadRadio(
                value: PomoDisplayMode.pinned,
                padding: const EdgeInsets.symmetric(vertical: 12),
                label: Text(l.pomoLinuxPinned),
              ),
            ],
            onChanged: (mode) {
              if (mode == null) return;
              unawaited(
                c.updatePreferences((p) => p.copyWith(displayMode: mode)),
              );
            },
          ),
        ),
        if (pinned)
          SettingsRow(
            title: l.pomoLinuxMonitor,
            control: Semantics(
              label: l.pomoLinuxMonitor,
              child: ShadSelect<String>(
                key: ValueKey('$selectedId:${names.keys.join(',')}'),
                initialValue: selectedId,
                enabled: names.isNotEmpty,
                placeholder: Text(l.pomoLinuxSelectMonitor),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                options: [
                  if (selectedId != null && !names.containsKey(selectedId))
                    ShadOption(
                      value: selectedId,
                      child: Text(monitorLabel(selectedId)),
                    ),
                  for (final entry in names.entries)
                    ShadOption(value: entry.key, child: Text(entry.value)),
                ],
                selectedOptionBuilder: (context, id) => Text(monitorLabel(id)),
                onChanged: (id) {
                  if (id == null || !names.containsKey(id)) return;
                  unawaited(
                    c.updatePreferences((p) => p.copyWith(pinnedDisplayId: id)),
                  );
                },
              ),
            ),
          ),
        SettingsRow(
          title: l.pomoLinuxCrossDisplayDrag,
          subtitle: pinned
              ? l.pomoLinuxCrossDisplayDragPinned
              : l.pomoLinuxCrossDisplayDragDescription,
          controlWidth: 48,
          control: Semantics(
            label: l.pomoLinuxCrossDisplayDrag,
            child: ShadSwitch(
              value: prefs.allowCrossDisplayDrag,
              enabled: !pinned,
              onChanged: (value) => unawaited(
                c.updatePreferences(
                  (p) => p.copyWith(allowCrossDisplayDrag: value),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
