import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadButton, ShadInput, ShadSwitch, LucideIcons;
import 'package:uuid/uuid.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:pomodoist/ui/distractions/view_models/distraction_view_model.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

class DistractionSettings extends ConsumerWidget {
  const DistractionSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(distractionViewModelProvider),
        commands = ref.watch(distractionCommandsProvider);
    if (!state.available || commands == null) return const SizedBox.shrink();
    final l = context.l10n;
    Future<void> act(Future<void> action) async {
      try {
        await action;
      } on Object catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    final profile = state.profiles
        .where((p) => p.id == state.profileId)
        .firstOrNull;
    final resources = {
      for (final a in [...state.inventory, ...state.assignments])
        '${a.kind}:${a.id}': a,
    }.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          l.distractionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l.distractionDescription),
        SettingsRow(
          title: l.distractionProfile,
          subtitle: l.distractionBeforeStart,
          control: DropdownButtonFormField<String>(
            initialValue: profile?.id ?? '',
            isExpanded: true,
            decoration: const InputDecoration(),
            items: [
              DropdownMenuItem(value: '', child: Text(l.distractionNone)),
              for (final p in state.profiles)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: state.active
                ? null
                : (id) => unawaited(
                    act(
                      commands.configure(profileId: id, clearProfile: id == ''),
                    ),
                  ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShadButton.outline(
              height: 48,
              leading: const Icon(LucideIcons.plus, size: 16),
              onPressed: () => _editProfile(context, ref),
              child: Text(l.distractionAddProfile),
            ),
            if (profile != null)
              ShadButton.outline(
                height: 48,
                onPressed: () => _editProfile(context, ref, profile),
                child: Text(l.distractionEditProfile),
              ),
          ],
        ),
        SettingsRow(
          title: l.distractionStrictExit,
          subtitle: l.distractionStrictDescription,
          control: DropdownButtonFormField<int>(
            initialValue: state.strictExitSeconds,
            items: [
              DropdownMenuItem(value: 60, child: Text(l.distractionWait60)),
              DropdownMenuItem(
                value: 0,
                child: Text(l.distractionConfirmImmediately),
              ),
            ],
            onChanged: state.active
                ? null
                : (v) =>
                      unawaited(act(commands.configure(strictExitSeconds: v))),
          ),
        ),
        SettingsRow(
          title: l.distractionDiscovery,
          subtitle: l.distractionDiscoveryPrivacy,
          controlWidth: 48,
          control: ShadSwitch(
            value: state.discovery,
            onChanged: (v) => unawaited(act(commands.configure(discovery: v))),
          ),
        ),
        SettingsRow(
          title: l.distractionAttempts,
          subtitle: l.distractionAttemptsPrivacy,
          controlWidth: 48,
          control: ShadSwitch(
            value: state.collectAttempts,
            onChanged: (v) =>
                unawaited(act(commands.configure(collectAttempts: v))),
          ),
        ),
        SettingsRow(
          title: l.distractionAutomatic,
          subtitle: l.distractionAutomaticDescription,
          controlWidth: 48,
          control: ShadSwitch(
            value: state.automatic,
            onChanged: (v) => unawaited(act(commands.configure(automatic: v))),
          ),
        ),
        Text(
          state.local
              ? l.distractionLocal
              : state.online
              ? l.distractionShared
              : l.distractionOffline,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          state.nativeApplied
              ? l.distractionNativeApplied
              : state.nativeSupported
              ? l.distractionNativeReady
              : l.distractionNativeUnavailable,
        ),
        if (state.nativeReason != null)
          Text(
            state.nativeReason!,
            style: TextStyle(color: context.appColors.secondaryText),
          ),
        const SizedBox(height: 12),
        SettingsRow(
          title: l.distractionChrome,
          subtitle: state.pairingCode == null
              ? l.distractionPairDescription
              : l.distractionPairCode(state.pairingCode!, state.bridgePort),
          control: ShadButton.outline(
            height: 48,
            onPressed: () => unawaited(act(commands.pair())),
            child: Text(l.distractionPair),
          ),
        ),
        if (state.error != null)
          Text(state.error!, style: TextStyle(color: context.appColors.error)),
        if (state.conflict) ...[
          Text(l.distractionConflict),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton(
                height: 48,
                onPressed: () => unawaited(act(commands.joinShared())),
                child: Text(l.distractionJoinShared),
              ),
              ShadButton.outline(
                height: 48,
                onPressed: () => unawaited(act(commands.finishLocal())),
                child: Text(l.distractionFinishLocal),
              ),
            ],
          ),
        ],
        if (state.active)
          ShadButton.outline(
            height: 48,
            onPressed: () => unawaited(act(commands.requestExit())),
            child: Text(l.distractionStopEverywhere),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                l.distractionResources,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ShadButton.ghost(
              height: 48,
              onPressed: () => _addResource(context, ref),
              child: Text(l.distractionAddSite),
            ),
          ],
        ),
        if (resources.isEmpty) Text(l.distractionNoResources),
        for (final a in resources)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(a.name, style: Theme.of(context).textTheme.titleSmall),
                Text(a.id, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String>(
                        initialValue: a.category,
                        decoration: InputDecoration(
                          labelText: l.distractionCategory,
                        ),
                        items: [
                          for (final c in distractionCategories)
                            DropdownMenuItem(
                              value: c,
                              child: Text(_category(context, c)),
                            ),
                        ],
                        onChanged: (c) => unawaited(
                          act(
                            commands.saveAssignment(
                              ResourceAssignment.fromJson({
                                ...a.json,
                                'category': c,
                                'source': 'manual',
                                'updatedAt': DateTime.now()
                                    .toUtc()
                                    .toIso8601String(),
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (profile != null)
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              profile.overrides
                                  .where(
                                    (r) =>
                                        r['id'] == a.id && r['kind'] == a.kind,
                                  )
                                  .firstOrNull?['action'] ??
                              'category',
                          decoration: InputDecoration(
                            labelText: l.distractionException,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'category',
                              child: Text(l.distractionUseCategory),
                            ),
                            DropdownMenuItem(
                              value: 'allow',
                              child: Text(l.distractionAllow),
                            ),
                            DropdownMenuItem(
                              value: 'block',
                              child: Text(l.distractionBlock),
                            ),
                          ],
                          onChanged: (action) => unawaited(
                            act(
                              commands.saveProfile(
                                DistractionProfile.fromJson({
                                  ...profile.json,
                                  'updatedAt': DateTime.now()
                                      .toUtc()
                                      .toIso8601String(),
                                  'overrides': [
                                    ...profile.overrides.where(
                                      (r) =>
                                          r['id'] != a.id ||
                                          r['kind'] != a.kind,
                                    ),
                                    if (action != 'category')
                                      {
                                        'kind': a.kind,
                                        'id': a.id,
                                        'action': action,
                                      },
                                  ],
                                }),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ShadButton.ghost(
                      height: 48,
                      onPressed: () => unawaited(act(commands.classify(a))),
                      child: Text(l.distractionClassify),
                    ),
                  ],
                ),
                if (a.source == 'automatic') Text(l.distractionAutomaticSource),
                if (a.json['sources'] is List)
                  for (final source in a.json['sources'] as List)
                    SelectableText(
                      '${source['title']} — ${source['url']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
              ],
            ),
          ),
        for (final d in state.devices)
          _DeviceCoverage(device: d, revision: state.sessionRevision),
      ],
    );
  }
}

String _category(BuildContext context, String c) => switch (c) {
  'social' => context.l10n.distractionSocial,
  'messaging' => context.l10n.distractionMessaging,
  'video' => context.l10n.distractionVideo,
  'music' => context.l10n.distractionMusic,
  'games' => context.l10n.distractionGames,
  'news' => context.l10n.distractionNews,
  'shopping' => context.l10n.distractionShopping,
  'education' => context.l10n.distractionEducation,
  'development' => context.l10n.distractionDevelopment,
  'productivity' => context.l10n.distractionProductivity,
  'other' => context.l10n.distractionOther,
  _ => context.l10n.distractionUnclassified,
};
Future<void> _editProfile(
  BuildContext context,
  WidgetRef ref, [
  DistractionProfile? current,
]) async {
  final l = context.l10n,
      name = TextEditingController(text: current?.name ?? '');
  final categories = {...?current?.blockedCategories};
  var pause = current?.blockOnPause ?? true,
      short = current?.blockOnShortBreak ?? false,
      long = current?.blockOnLongBreak ?? false;
  String? error;
  bool saving = false;
  await showDialog<void>(
    context: context,
    animationStyle: AnimationStyle(
      duration: AppMotion.duration(context, AppMotion.popup),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          current == null ? l.distractionAddProfile : l.distractionEditProfile,
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShadInput(
                  controller: name,
                  placeholder: Text(l.distractionProfileName),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in distractionCategories.where(
                      (c) => c != 'unclassified',
                    ))
                      FilterChip(
                        label: Text(_category(ctx, c)),
                        selected: categories.contains(c),
                        onSelected: (v) => setState(
                          () => v ? categories.add(c) : categories.remove(c),
                        ),
                      ),
                  ],
                ),
                SwitchListTile(
                  title: Text(l.distractionOnPause),
                  value: pause,
                  onChanged: (v) => setState(() => pause = v),
                ),
                SwitchListTile(
                  title: Text(l.distractionOnShortBreak),
                  value: short,
                  onChanged: (v) => setState(() => short = v),
                ),
                SwitchListTile(
                  title: Text(l.distractionOnLongBreak),
                  value: long,
                  onChanged: (v) => setState(() => long = v),
                ),
                if (error != null)
                  Text(error!, style: TextStyle(color: ctx.appColors.error)),
              ],
            ),
          ),
        ),
        actions: [
          ShadButton.ghost(
            onPressed: saving ? null : () => Navigator.pop(ctx),
            child: Text(l.commonCancel),
          ),
          ShadButton(
            enabled: !saving,
            onPressed: () async {
              if (name.text.trim().isEmpty) {
                setState(() => error = l.distractionProfileName);
                return;
              }
              setState(() => saving = true);
              try {
                await ref
                    .read(distractionCommandsProvider)!
                    .saveProfile(
                      DistractionProfile.fromJson({
                        ...?current?.json,
                        'id': current?.id ?? const Uuid().v4(),
                        'name': name.text.trim(),
                        'blockedCategories': categories.toList(),
                        'overrides': current?.overrides ?? [],
                        'blockOnPause': pause,
                        'blockOnShortBreak': short,
                        'blockOnLongBreak': long,
                        'updatedAt': DateTime.now().toUtc().toIso8601String(),
                      }),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              } on Object catch (e) {
                if (ctx.mounted) {
                  setState(() {
                    error = '$e';
                    saving = false;
                  });
                }
              }
            },
            child: Text(l.commonSave),
          ),
        ],
      ),
    ),
  );
  name.dispose();
}

Future<void> _addResource(BuildContext context, WidgetRef ref) async {
  final input = TextEditingController();
  final l = context.l10n;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(l.distractionAddSite),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: input,
              placeholder: const Text('youtube.com'),
            ),
            if (error != null) Text(error!),
          ],
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonCancel),
          ),
          ShadButton(
            onPressed: () async {
              final id = normalizeDomain(input.text.trim());
              if (id == null) {
                setState(() => error = l.distractionInvalidDomain);
                return;
              }
              try {
                await ref
                    .read(distractionCommandsProvider)!
                    .saveAssignment(
                      ResourceAssignment.fromJson({
                        'id': id,
                        'kind': 'domain',
                        'name': id,
                        'category': 'unclassified',
                        'source': 'manual',
                        'updatedAt': DateTime.now().toUtc().toIso8601String(),
                      }),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              } on Object catch (e) {
                if (ctx.mounted) setState(() => error = '$e');
              }
            },
            child: Text(l.commonSave),
          ),
        ],
      ),
    ),
  );
  input.dispose();
}

class _DeviceCoverage extends StatelessWidget {
  const _DeviceCoverage({required this.device, required this.revision});
  final Map<String, dynamic> device;
  final int? revision;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final seen = DateTime.tryParse('${device['lastSeenAt']}');
    final connected =
        seen != null &&
        DateTime.now().difference(seen) < const Duration(seconds: 45);
    final caps = device['capabilities'] is Map
        ? device['capabilities'] as Map
        : const {};
    final applied =
        connected &&
        device['detached'] != true &&
        revision != null &&
        device['appliedRevision'] == revision &&
        (caps['nativeApplied'] == true || caps['websiteApplied'] == true);
    final date = seen == null
        ? '—'
        : '${MaterialLocalizations.of(context).formatMediumDate(seen.toLocal())} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(seen.toLocal()))}';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${device['name'] ?? device['platform'] ?? device['deviceId']} · ${device['detached'] == true
                ? l.distractionDetached
                : connected
                ? l.distractionConnected
                : l.distractionDisconnected}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(applied ? l.distractionProtected : l.distractionNotConfirmed),
          Text(
            device['platform'] == 'chrome'
                ? l.distractionChrome
                : caps['native'] == true
                ? l.distractionNativeReady
                : l.distractionNativeUnavailable,
          ),
          if (device['platform'] == 'chrome')
            Text(
              l.distractionIncognito(
                caps['incognito'] == true
                    ? l.distractionAllow
                    : l.distractionBlock,
              ),
            ),
          Text(
            l.distractionLastSeen(date),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
