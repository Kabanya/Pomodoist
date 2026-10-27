import 'package:pomodoist/ui/distractions/view_models/blocking_view_model.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadButton, ShadInput, LucideIcons;
import 'package:uuid/uuid.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:pomodoist/ui/distractions/view_models/distraction_view_model.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';

class DistractionSettings extends ConsumerWidget {
  const DistractionSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(distractionViewModelProvider).available) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: ShadButton.outline(
        height: 48,
        leading: const Icon(LucideIcons.shield, size: 16),
        onPressed: () => context.go('/blocking'),
        child: Text(context.l10n.blockingTitle),
      ),
    );
  }
}

class DistractionResources extends ConsumerWidget {
  const DistractionResources({
    super.key,
    required this.profileId,
    required this.classify,
  });
  final String? profileId;
  final Future<void> Function(ResourceAssignment) classify;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(blockingViewModelProvider);
    final saving = editor.saving, error = editor.error;
    Future<void> act(Future<void> Function() action) async {
      await ref.read(blockingViewModelProvider.notifier).save(action);
    }

    final state = ref.watch(distractionViewModelProvider);
    final commands = ref.watch(distractionCommandsProvider)!;
    final l = context.l10n;
    final profile = state.profiles.where((p) => p.id == profileId).firstOrNull;
    final resources = {
      for (final a in [...state.inventory, ...state.assignments])
        '${a.kind}:${a.id}': a,
    }.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (saving) const LinearProgressIndicator(minHeight: 2),
        if (error != null)
          Text(error, style: TextStyle(color: context.appColors.error)),
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
              onPressed: saving ? null : () => _addResource(context, ref),
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
                        key: ValueKey(
                          '${a.kind}:${a.id}:${a.category}:$saving',
                        ),
                        initialValue: a.category,
                        decoration: InputDecoration(
                          labelText: l.distractionCategory,
                        ),
                        items: [
                          for (final c in distractionCategories)
                            DropdownMenuItem(
                              value: c,
                              child: Text(distractionCategoryLabel(context, c)),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (c) => unawaited(
                                act(
                                  () => commands.saveAssignment(
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
                      _DistractionResourceException(
                        profile: profile,
                        resource: a,
                      ),
                    ShadButton.ghost(
                      height: 48,
                      onPressed: saving
                          ? null
                          : () => unawaited(act(() => classify(a))),
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
      ],
    );
  }
}

// Dart AOT hoisted profile JSON reads before the parent's null guard on macOS.
class _DistractionResourceException extends ConsumerWidget {
  const _DistractionResourceException({
    required this.profile,
    required this.resource,
  });

  final DistractionProfile profile;
  final ResourceAssignment resource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saving = ref.watch(blockingViewModelProvider).saving;
    final commands = ref.watch(distractionCommandsProvider)!;
    final l = context.l10n;
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        key: ValueKey(
          '${profile.id}:${resource.kind}:${resource.id}:${profile.json['updatedAt']}:$saving',
        ),
        initialValue:
            profile.overrides
                .where(
                  (r) => r['id'] == resource.id && r['kind'] == resource.kind,
                )
                .firstOrNull?['action'] ??
            'category',
        decoration: InputDecoration(labelText: l.distractionException),
        items: [
          DropdownMenuItem(
            value: 'category',
            child: Text(l.distractionUseCategory),
          ),
          DropdownMenuItem(value: 'allow', child: Text(l.distractionAllow)),
          DropdownMenuItem(value: 'block', child: Text(l.distractionBlock)),
        ],
        onChanged: saving
            ? null
            : (action) => unawaited(
                ref
                    .read(blockingViewModelProvider.notifier)
                    .save(
                      () => commands.saveProfile(
                        DistractionProfile.fromJson({
                          ...profile.json,
                          'updatedAt': DateTime.now().toUtc().toIso8601String(),
                          'overrides': [
                            ...profile.overrides.where(
                              (r) =>
                                  r['id'] != resource.id ||
                                  r['kind'] != resource.kind,
                            ),
                            if (action != 'category')
                              {
                                'kind': resource.kind,
                                'id': resource.id,
                                'action': action,
                              },
                          ],
                        }),
                      ),
                    ),
              ),
      ),
    );
  }
}

String distractionCategoryLabel(BuildContext context, String c) => switch (c) {
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
Future<void> showDistractionProfileEditor(
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
                        label: Text(distractionCategoryLabel(ctx, c)),
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
                final saved = await ref
                    .read(blockingViewModelProvider.notifier)
                    .save(
                      () => ref
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
                              'updatedAt': DateTime.now()
                                  .toUtc()
                                  .toIso8601String(),
                            }),
                          ),
                    );
                if (!saved) {
                  throw StateError(
                    ref.read(blockingViewModelProvider).error ??
                        l.blockingSaving,
                  );
                }
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
                final saved = await ref
                    .read(blockingViewModelProvider.notifier)
                    .save(
                      () => ref
                          .read(distractionCommandsProvider)!
                          .saveAssignment(
                            ResourceAssignment.fromJson({
                              'id': id,
                              'kind': 'domain',
                              'name': id,
                              'category': 'unclassified',
                              'source': 'manual',
                              'updatedAt': DateTime.now()
                                  .toUtc()
                                  .toIso8601String(),
                            }),
                          ),
                    );
                if (!saved) {
                  throw StateError(
                    ref.read(blockingViewModelProvider).error ??
                        l.blockingSaving,
                  );
                }
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

class DistractionDeviceCoverage extends StatelessWidget {
  const DistractionDeviceCoverage({
    super.key,
    required this.device,
    required this.revision,
  });
  final Map<String, dynamic> device;
  final int? revision;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final seen = DateTime.tryParse('${device['lastSeenAt']}');
    final status = distractionDeviceStatus(
      device,
      revision: revision,
      now: DateTime.now(),
    );
    final caps = device['capabilities'] is Map
        ? device['capabilities'] as Map
        : const {};
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
                : status.connected
                ? l.distractionConnected
                : l.distractionDisconnected}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            status.applied ? l.distractionProtected : l.distractionNotConfirmed,
          ),
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
