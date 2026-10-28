import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadButton, ShadSwitch, LucideIcons, SvgPicture;
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/ui/billing/view_models/billing_view_model.dart';
import 'package:pomodoist/ui/billing/widgets/launch_offer_paywall.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/distractions/view_models/blocking_view_model.dart';
import 'package:pomodoist/ui/distractions/view_models/distraction_view_model.dart';
import 'package:pomodoist/ui/distractions/widgets/distraction_settings.dart';
import 'package:pomodoist/ui/focus/view_models/focus_view_model.dart';
import 'package:pomodoist/ui/focus/widgets/focus_preset_localizations.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

class BlockingScreen extends ConsumerWidget {
  const BlockingScreen({super.key});

  Future<void> _paywall(BuildContext context) => showDialog<void>(
    context: context,
    animationStyle: AnimationStyle(
      duration: AppMotion.duration(context, AppMotion.popup),
    ),
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: LaunchOfferPaywall(
            compact: true,
            showPlansWhenActive: true,
            onClose: () => Navigator.pop(ctx),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(distractionViewModelProvider);
    final l = context.l10n;
    if (!state.available) {
      return Center(child: Text(l.distractionNativeUnavailable));
    }
    final focus = ref.watch(focusViewModelProvider);
    final presetsExpanded = ref.watch(blockingPresetsExpandedProvider);
    final visiblePresets = presetsExpanded
        ? focus.presets
        : focus.presets.take(3);
    final editor = ref.watch(blockingViewModelProvider);
    final vm = ref.read(blockingViewModelProvider.notifier);
    final commands = ref.watch(distractionCommandsProvider)!;
    final billing = ref.watch(billingViewModelProvider);
    final automaticAction = automaticCategoryAction(billing, true);
    final preset = selectedFocusPresetOrDefault(
      focus.presets,
      editor.selectedPresetId,
    );
    final profileId = preset?.effectiveDistractionProfileId(state.profileId);
    final profile = state.profiles.where((p) => p.id == profileId).firstOrNull;
    final missing = profileId != null && profile == null;
    final active = state.active || focus.run != null;
    final busy = editor.saving;
    final now = DateTime.now();
    final chromeStatuses = state.devices
        .where((device) => device['platform'] == 'chrome')
        .map(
          (device) => distractionDeviceStatus(
            device,
            revision: state.sessionRevision,
            now: now,
          ),
        )
        .toList();
    final usedBy = focus.presets.where(
      (p) => p.effectiveDistractionProfileId(state.profileId) == profileId,
    );
    Future<void> classify(ResourceAssignment resource) async {
      final action = automaticCategoryAction(
        ref.read(billingViewModelProvider),
        true,
      );
      if (action == AutomaticCategoryAction.wait) {
        throw StateError(l.settingsSubscriptionError);
      }
      if (action == AutomaticCategoryAction.paywall) {
        await _paywall(context);
        return;
      }
      await commands.classify(resource);
    }

    Future<void> resources() => showDialog<void>(
      context: context,
      animationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.popup),
      ),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: MediaQuery.sizeOf(ctx).height * .85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ShadButton.ghost(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l.commonClose),
                  ),
                ),
                DistractionResources(profileId: profileId, classify: classify),
              ],
            ),
          ),
        ),
      ),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    Widget toggle(String title, bool value, ValueChanged<bool>? changed) =>
        SettingsRow(
          title: title,
          controlWidth: 48,
          control: Semantics(
            label: title,
            child: ShadSwitch(value: value, onChanged: changed),
          ),
        );
    Widget protectionRow({
      required Widget icon,
      required String title,
      required String subtitle,
      required bool enabled,
    }) {
      final colors = context.appColors;
      final tint = enabled
          ? Color.alphaBlend(
              colors.success.withValues(alpha: .12),
              colors.canvas,
            )
          : colors.surfaceTint;
      final statusColor = enabled ? colors.success : colors.secondaryText;
      return MergeSemantics(
        child: SettingsRow(
          leading: icon,
          title: title,
          subtitle: subtitle,
          controlWidth: MediaQuery.textScalerOf(
            context,
          ).scale(156).clamp(156.0, 280.0),
          control: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: tint,
                shape: const StadiumBorder(),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        enabled
                            ? LucideIcons.circleCheck
                            : LucideIcons.circlePause,
                        size: 20,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        enabled ? l.blockingEnabled : l.blockingDisabled,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: themeContrastRatio(statusColor, tint) >= 4.5
                              ? statusColor
                              : colors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preset != null) ...[
          Text(
            preset.displayName(l),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            l.blockingRhythm(
              preset.workSeconds ~/ 60,
              preset.shortBreakSeconds ~/ 60,
              preset.longBreakSeconds ~/ 60,
              preset.intervalsBeforeLongBreak,
            ),
            style: TextStyle(color: context.appColors.secondaryText),
          ),
          heading(l.distractionProfile),
          DropdownButtonFormField<String>(
            key: ValueKey(
              '${preset.id}:$profileId:${preset.distractionProfileConfigured}:$busy',
            ),
            initialValue: profileId ?? '',
            decoration: InputDecoration(labelText: l.distractionProfile),
            isExpanded: true,
            items: [
              DropdownMenuItem(value: '', child: Text(l.distractionNone)),
              if (missing)
                DropdownMenuItem(
                  value: profileId,
                  child: Text(l.blockingProfileMissing),
                ),
              for (final p in state.profiles)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: busy
                ? null
                : (id) =>
                      unawaited(vm.setProfile(preset.id, id == '' ? null : id)),
          ),
          const SizedBox(height: 8),
          if (profile != null)
            Text(
              l.blockingSharedPresets(
                usedBy.map((p) => p.displayName(l)).join(', '),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (active)
            Text(
              l.distractionBeforeStart,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (missing) ...[
            Text(
              l.blockingProfileMissing,
              style: TextStyle(color: context.appColors.error),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ShadButton.ghost(
                onPressed: busy
                    ? null
                    : () => unawaited(vm.save(commands.reload)),
                child: Text(l.commonRetry),
              ),
            ),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton.ghost(
                height: 48,
                leading: const Icon(LucideIcons.plus, size: 16),
                onPressed: busy
                    ? null
                    : () => showDistractionProfileEditor(context, ref),
                child: Text(l.distractionAddProfile),
              ),
              if (profile != null)
                ShadButton.ghost(
                  height: 48,
                  onPressed: busy
                      ? null
                      : () =>
                            showDistractionProfileEditor(context, ref, profile),
                  child: Text(l.distractionEditProfile),
                ),
              ShadButton.ghost(
                height: 48,
                onPressed: busy ? null : resources,
                child: Text(l.distractionResources),
              ),
            ],
          ),
          if (profile != null) ...[
            heading(l.blockingWhatToClose),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in distractionCategories.where(
                  (c) => c != 'unclassified',
                ))
                  FilterChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: Text(distractionCategoryLabel(context, c)),
                    selected: profile.blockedCategories.contains(c),
                    onSelected: busy
                        ? null
                        : (selected) => unawaited(
                            vm.updateProfile(profile.id, {
                              'blockedCategories': [
                                ...profile.blockedCategories.where(
                                  (v) => v != c,
                                ),
                                if (selected) c,
                              ],
                            }),
                          ),
                  ),
              ],
            ),
            heading(l.blockingWhatToKeep),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rule in profile.overrides.where(
                  (r) => r['action'] == 'allow',
                ))
                  InputChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: Text('${rule['id']}'),
                    deleteButtonTooltipMessage: l.commonDelete,
                    onDeleted: busy
                        ? null
                        : () => unawaited(
                            vm.updateProfile(profile.id, {
                              'overrides': profile.overrides
                                  .where(
                                    (r) =>
                                        r['id'] != rule['id'] ||
                                        r['kind'] != rule['kind'],
                                  )
                                  .toList(),
                            }),
                          ),
                  ),
                ShadButton.outline(
                  height: 48,
                  onPressed: busy ? null : resources,
                  leading: const Icon(LucideIcons.plus, size: 16),
                  child: Text(l.distractionException),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(l.blockingBehavior),
              children: [
                toggle(
                  l.distractionOnPause,
                  profile.blockOnPause,
                  busy || (active && state.strict)
                      ? null
                      : (v) => unawaited(
                          vm.updateProfile(profile.id, {'blockOnPause': v}),
                        ),
                ),
                toggle(
                  l.distractionOnShortBreak,
                  profile.blockOnShortBreak,
                  busy
                      ? null
                      : (v) => unawaited(
                          vm.updateProfile(profile.id, {
                            'blockOnShortBreak': v,
                          }),
                        ),
                ),
                toggle(
                  l.distractionOnLongBreak,
                  profile.blockOnLongBreak,
                  busy
                      ? null
                      : (v) => unawaited(
                          vm.updateProfile(profile.id, {'blockOnLongBreak': v}),
                        ),
                ),
                SettingsRow(
                  title: l.distractionStrictExit,
                  subtitle: l.distractionStrictDescription,
                  control: DropdownButtonFormField<int>(
                    initialValue: state.strictExitSeconds,
                    decoration: InputDecoration(
                      labelText: l.distractionStrictExit,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 60,
                        child: Text(l.distractionWait60),
                      ),
                      DropdownMenuItem(
                        value: 0,
                        child: Text(l.distractionConfirmImmediately),
                      ),
                    ],
                    onChanged: active || busy
                        ? null
                        : (v) => unawaited(
                            vm.save(
                              () => commands.configure(strictExitSeconds: v),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 24),
        Divider(color: context.appColors.border),
        heading(l.blockingDevices),
        protectionRow(
          icon: Icon(
            LucideIcons.copy,
            size: 32,
            color: context.appColors.secondaryText,
          ),
          title: l.blockingApps,
          subtitle:
              state.nativeReason ??
              (state.nativeApplied
                  ? l.distractionNativeApplied
                  : state.nativeSupported
                  ? l.distractionNativeReady
                  : l.distractionNativeUnavailable),
          enabled: state.nativeApplied,
        ),
        Divider(height: 1, color: context.appColors.border),
        protectionRow(
          icon: SvgPicture.asset(
            'assets/branding/chrome-logo.svg',
            width: 32,
            height: 32,
          ),
          title: 'Google Chrome',
          subtitle:
              '${l.distractionChrome} · ${chromeStatuses.any((s) => s.connected) ? l.distractionConnected : l.distractionDisconnected}',
          enabled: state.active && chromeStatuses.any((s) => s.applied),
        ),
        SettingsRow(
          title: l.distractionChrome,
          subtitle: state.pairingCode == null
              ? l.distractionPairDescription
              : l.distractionPairCode(state.pairingCode!, state.bridgePort),
          control: ShadButton.outline(
            height: 48,
            onPressed: busy ? null : () => unawaited(vm.save(commands.pair)),
            child: Text(l.distractionPair),
          ),
        ),
        SettingsRow(
          title: l.distractionDiscovery,
          subtitle: l.distractionDiscoveryPrivacy,
          controlWidth: 48,
          control: Semantics(
            label: l.distractionDiscovery,
            child: ShadSwitch(
              value: state.discovery,
              onChanged: busy
                  ? null
                  : (v) => unawaited(
                      vm.save(() => commands.configure(discovery: v)),
                    ),
            ),
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                state.local
                    ? l.distractionLocal
                    : state.online
                    ? l.distractionShared
                    : l.distractionOffline,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                l.blockingDeviceDetails,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          children: [
            SettingsRow(
              title: l.distractionAttempts,
              subtitle: l.distractionAttemptsPrivacy,
              controlWidth: 48,
              control: Semantics(
                label: l.distractionAttempts,
                child: ShadSwitch(
                  value: state.collectAttempts,
                  onChanged: busy
                      ? null
                      : (v) => unawaited(
                          vm.save(() => commands.configure(collectAttempts: v)),
                        ),
                ),
              ),
            ),
            for (final device in state.devices)
              DistractionDeviceCoverage(
                device: device,
                revision: state.sessionRevision,
              ),
            if (state.conflict) ...[
              Text(l.distractionConflict),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ShadButton.outline(
                    onPressed: busy
                        ? null
                        : () => unawaited(vm.save(commands.joinShared)),
                    child: Text(l.distractionJoinShared),
                  ),
                  ShadButton.outline(
                    onPressed: busy
                        ? null
                        : () => unawaited(vm.save(commands.finishLocal)),
                    child: Text(l.distractionFinishLocal),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        Divider(color: context.appColors.border),
        Row(
          children: [
            Expanded(
              child: Text(
                l.distractionAutomatic,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Chip(
              label: Text(l.settingsPlanPro),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 12),
            Semantics(
              label: l.distractionAutomatic,
              child: ShadSwitch(
                value: state.automatic,
                onChanged:
                    busy || automaticAction == AutomaticCategoryAction.wait
                    ? null
                    : (v) {
                        if (v &&
                            automaticAction ==
                                AutomaticCategoryAction.paywall) {
                          unawaited(_paywall(context));
                          return;
                        }
                        unawaited(
                          vm.save(() => commands.configure(automatic: v)),
                        );
                      },
              ),
            ),
          ],
        ),
        Text(l.distractionAutomaticDescription),
        if (automaticAction == AutomaticCategoryAction.wait) ...[
          if (billing.loading) const LinearProgressIndicator(minHeight: 2),
          if (billing.error != null)
            ShadButton.ghost(
              onPressed: () =>
                  ref.read(billingViewModelProvider.notifier).reload(),
              child: Text(l.commonRetry),
            ),
        ],
        const SizedBox(height: 24),
        if (busy) ...[
          const LinearProgressIndicator(minHeight: 2),
          Text(l.blockingSaving),
        ],
        if (editor.error != null)
          Text(editor.error!, style: TextStyle(color: context.appColors.error)),
        if (state.error != null)
          Text(state.error!, style: TextStyle(color: context.appColors.error)),
        if (focus.loadError != null)
          Text(
            '${focus.loadError}',
            style: TextStyle(color: context.appColors.error),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ShadButton(
            height: 48,
            enabled:
                !busy &&
                (active ||
                    (preset != null &&
                        !missing &&
                        !focus.loading &&
                        focus.loadError == null)),
            onPressed: () async {
              if (active) {
                context.go('/focus');
                return;
              }
              final started = await vm.save(
                () => ref
                    .read(focusViewModelProvider.notifier)
                    .startFocus(preset!),
              );
              if (started && context.mounted) context.go('/focus');
            },
            child: Text(active ? l.blockingCurrentFocus : l.startFocus),
          ),
        ),
      ],
    );

    Widget presetTile(FocusPresetItem p, {required bool compact}) {
      final id = p.effectiveDistractionProfileId(state.profileId);
      final name = state.profiles.where((v) => v.id == id).firstOrNull?.name;
      final selected = p.id == preset?.id;
      final colors = context.appColors;
      final textTheme = Theme.of(context).textTheme;
      Widget breakDuration(int seconds, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${seconds ~/ 60} ${l.minutesSuffix}',
              style: AppTheme.monoTextStyle.copyWith(
                fontSize: 14,
                color: colors.primaryText,
              ),
            ),
            Text(label, style: textTheme.bodySmall),
          ],
        ),
      );
      final work = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${p.workSeconds ~/ 60}',
                style: AppTheme.monoTextStyle.copyWith(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: colors.accent,
                ),
              ),
              Text(l.minutesSuffix, style: textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(l.navFocus, style: textTheme.bodySmall),
        ],
      );
      final breaks = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          breakDuration(p.shortBreakSeconds, l.shortBreak),
          breakDuration(p.longBreakSeconds, l.longBreak),
        ],
      );
      return SizedBox(
        width: compact ? 320 : double.infinity,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: selected ? colors.accent : colors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => vm.selectPreset(p.id),
              child: Semantics(
                selected: selected,
                button: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.displayName(l),
                                style: textTheme.titleSmall,
                              ),
                            ),
                            if (selected) ...[
                              const SizedBox(width: 8),
                              ExcludeSemantics(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.accentFill,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      LucideIcons.check,
                                      size: 14,
                                      color: colors.onAccent,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth <
                                MediaQuery.textScalerOf(context).scale(260)) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  work,
                                  const SizedBox(height: 12),
                                  breaks,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(flex: 2, child: work),
                                SizedBox(
                                  height: 64,
                                  child: VerticalDivider(
                                    width: 25,
                                    color: colors.border,
                                  ),
                                ),
                                Expanded(flex: 3, child: breaks),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(height: 1, color: colors.border),
                      Ink(
                        color: colors.surfaceTint,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 72),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                ExcludeSemantics(
                                  child: Icon(
                                    id == null
                                        ? LucideIcons.shieldOff
                                        : LucideIcons.shield,
                                    size: 24,
                                    color: colors.secondaryText,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    id == null
                                        ? l.distractionNone
                                        : name ?? l.blockingProfileMissing,
                                    style: name == null
                                        ? textTheme.bodyMedium
                                        : textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final presetsToggle = Semantics(
      expanded: presetsExpanded,
      child: ShadButton.ghost(
        height: 44,
        onPressed: ref.read(blockingPresetsExpandedProvider.notifier).toggle,
        child: Text(
          presetsExpanded
              ? l.blockingCollapsePresets
              : l.blockingShowAllPresets,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        return SingleChildScrollView(
          padding: EdgeInsets.all(wide ? 32 : 16),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.blockingTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.blockingDescription,
                    style: TextStyle(color: context.appColors.secondaryText),
                  ),
                  const SizedBox(height: 32),
                  if (focus.loading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 320,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final p in visiblePresets)
                                presetTile(p, compact: false),
                              if (focus.presets.length > 3) presetsToggle,
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(child: detail),
                      ],
                    )
                  else ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final p in visiblePresets)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: presetTile(p, compact: true),
                            ),
                        ],
                      ),
                    ),
                    if (focus.presets.length > 3)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: presetsToggle,
                      ),
                    detail,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
