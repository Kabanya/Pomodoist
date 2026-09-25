import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadSwitch, ShadSelect, ShadOption;

import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/ui/google_calendar/widgets/google_calendar_settings_screen.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';
import 'package:pomodoist/ui/settings/widgets/settings_navigation.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_inbox_dialog.dart';
import 'package:pomodoist/ui/settings/widgets/settings_subscription.dart';
import 'package:pomodoist/ui/settings/widgets/account_sign_out_button.dart';
import 'package:pomodoist/ui/settings/widgets/account_nickname_dialog.dart';
import 'package:pomodoist/ui/settings/widgets/app_info_card.dart';
import 'package:pomodoist/ui/settings/widgets/csv_task_import_card.dart';
import 'package:pomodoist/ui/settings/widgets/theme_settings_card.dart';
import 'package:pomodoist/ui/settings/widgets/bottom_navigation_settings.dart';
import 'package:pomodoist/ui/settings/widgets/voice_transcription_settings_card.dart';
import 'package:pomodoist/ui/settings/widgets/pomodoist_account_actions.dart';
import 'package:pomodoist/ui/settings/widgets/auth_surfaces.dart';
import 'package:pomodoist/ui/settings/widgets/account_delete_dialog.dart';
import 'package:pomodoist/ui/settings/widgets/connected_agents_section.dart';
import 'package:pomodoist/ui/settings/view_models/connected_agents_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/settings_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/auth_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/task_list_settings.dart';
export 'package:pomodoist/ui/settings/widgets/login_screen.dart';
export 'package:pomodoist/ui/settings/widgets/register_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({this.location, this.signOutOverride, super.key});

  final Uri? location;
  final Future<void> Function()? signOutOverride;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final _navigation = SettingsNavigation(
    widget.location ?? Uri(path: '/settings'),
  );
  final _visited = <SettingsSection>{};
  late final _fade = AnimationController(vsync: this, value: 1);

  @override
  void initState() {
    super.initState();
    // The controller owns the first request; later visits refresh quietly.
    if (!ref.read(connectedAgentsViewModelProvider).isLoading) {
      unawaited(
        Future<void>.microtask(() {
          if (mounted) {
            return ref
                .read(connectedAgentsViewModelProvider.notifier)
                .refresh();
          }
        }),
      );
    }
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _navigation.selected;
    _navigation.syncLocation(widget.location ?? Uri(path: '/settings'));
    if (_navigation.selected != previous) {
      FocusManager.instance.primaryFocus?.unfocus();
      _fade.duration = AppMotion.duration(context, AppMotion.state);
      _fade.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _fade.value = 1;
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  String _title(SettingsSection section) {
    final l10n = context.l10n;
    return switch (section) {
      SettingsSection.general => l10n.settingsSectionGeneral,
      SettingsSection.appearance => l10n.settingsSectionAppearance,
      SettingsSection.tasksFocus => l10n.settingsSectionTasksFocus,
      SettingsSection.integrations => l10n.settingsSectionIntegrations,
      SettingsSection.account => l10n.settingsSectionAccount,
      SettingsSection.about => l10n.settingsAboutTitle,
    };
  }

  IconData _icon(SettingsSection section) => switch (section) {
    SettingsSection.general => LucideIcons.slidersHorizontal,
    SettingsSection.appearance => LucideIcons.palette,
    SettingsSection.tasksFocus => LucideIcons.timer,
    SettingsSection.integrations => LucideIcons.plug,
    SettingsSection.account => LucideIcons.userRound,
    SettingsSection.about => LucideIcons.info,
  };

  Widget _menu({required bool wide}) => ListView(
    padding: EdgeInsets.zero,
    children: [
      for (final section in SettingsSection.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Semantics(
            selected: wide && _navigation.selected == section,
            child: ShadButton.ghost(
              height: 48,
              mainAxisAlignment: MainAxisAlignment.start,
              backgroundColor: wide && _navigation.selected == section
                  ? context.appColors.accent.withValues(alpha: 0.10)
                  : null,
              foregroundColor: wide && _navigation.selected == section
                  ? context.appColors.accent
                  : context.appColors.primaryText,
              onPressed: () => context.go(settingsLocation(section).toString()),
              child: Expanded(
                child: Row(
                  children: [
                    Icon(_icon(section), size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_title(section), textAlign: TextAlign.start),
                    ),
                    if (!wide) const Icon(LucideIcons.chevronRight, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => SettingsSurface(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        _navigation.resolveLayout(wide: wide);
        final selected = _navigation.selected;
        if (selected != null) _visited.add(selected);
        return PopScope(
          canPop: wide || selected == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !wide && selected != null) {
              context.go(settingsLocation(null).toString());
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (!wide && selected != null) ...[
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () =>
                          context.go(settingsLocation(null).toString()),
                      icon: const Icon(LucideIcons.arrowLeft),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      context.l10n.settingsTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Offstage(
                      offstage: !wide,
                      child: ExcludeFocus(
                        excluding: !wide,
                        child: SizedBox(width: 216, child: _menu(wide: true)),
                      ),
                    ),
                    SizedBox(width: wide ? 32 : 0),
                    Expanded(
                      child: FadeTransition(
                        opacity: _fade.drive(
                          CurveTween(curve: AppMotion.curve),
                        ),
                        child: IndexedStack(
                          index: selected == null ? 0 : selected.index + 1,
                          children: [
                            ExcludeFocus(
                              excluding: selected != null,
                              child: _menu(wide: false),
                            ),
                            for (final section in SettingsSection.values)
                              TickerMode(
                                enabled: selected == section,
                                child: ExcludeFocus(
                                  excluding: selected != section,
                                  child: _visited.contains(section)
                                      ? ListView(
                                          key: PageStorageKey(
                                            'settings-${section.name}',
                                          ),
                                          padding: EdgeInsets.zero,
                                          children: [
                                            Text(
                                              _title(section),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleLarge,
                                            ),
                                            const SizedBox(height: 12),
                                            Consumer(
                                              builder: (context, ref, _) =>
                                                  _content(section, ref),
                                            ),
                                            const SizedBox(height: 24),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _content(SettingsSection section, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsViewModelProvider);
    final viewModel = ref.read(settingsViewModelProvider.notifier);
    switch (section) {
      case SettingsSection.general:
        final language = settings.language;
        return SettingsGroup(
          children: [
            SettingsRow(
              title: l10n.settingsLanguageTitle,
              subtitle: l10n.settingsLanguageSubtitle,
              control: ShadSelect<AppLanguage>(
                key: ValueKey(language),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                initialValue: language,
                options: [
                  for (final item in AppLanguage.values)
                    ShadOption(
                      value: item,
                      child: Text(
                        item == AppLanguage.system
                            ? l10n.settingsLanguageSystem
                            : item.nativeName,
                      ),
                    ),
                ],
                selectedOptionBuilder: (context, item) => Text(
                  item == AppLanguage.system
                      ? l10n.settingsLanguageSystem
                      : item.nativeName,
                ),
                onChanged: (value) {
                  if (value != null) {
                    saveSetting(context, viewModel.setLanguage(value));
                  }
                },
              ),
            ),
            if (settings.voiceModeSupported)
              const VoiceTranscriptionSettingsCard(),
            SettingsRow(
              title: l10n.settingsReturnRemindersTitle,
              subtitle: l10n.settingsReturnRemindersSubtitle,
              onTap: () => saveSetting(
                context,
                viewModel.setReengagement(!settings.reengagementEnabled),
              ),
              controlWidth: 48,
              control: ShadSwitch(
                key: const Key('settings-reengagement-notifications-switch'),
                value: settings.reengagementEnabled,
                onChanged: (value) =>
                    saveSetting(context, viewModel.setReengagement(value)),
              ),
            ),
            ListTile(
              key: const Key('settings-shortcuts-button'),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              leading: const Icon(LucideIcons.keyboard, size: 20),
              title: Text(l10n.settingsShortcutsTitle),
              subtitle: Text(l10n.settingsShortcutsSubtitle),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: () => context.push('/settings/shortcuts'),
            ),
          ],
        );
      case SettingsSection.appearance:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ThemeSettingsCard(),
            SizedBox(height: 24),
            BottomNavigationSettings(),
            SizedBox(height: 24),
            TaskListStyleSettings(),
          ],
        );
      case SettingsSection.tasksFocus:
        final style = settings.timerStyle;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DefaultTimedBlockDurationSettings(),
            const SizedBox(height: 24),
            SettingsGroup(
              children: [
                SettingsRow(
                  title: l10n.settingsTimerVisualTitle,
                  subtitle: l10n.settingsTimerVisualSubtitle,
                  control: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in FocusTimerVisualStyle.values)
                        ChoiceChip(
                          label: Text(
                            option == FocusTimerVisualStyle.bar
                                ? l10n.settingsTimerVisualBar
                                : l10n.settingsTimerVisualCircle,
                          ),
                          selected: option == style,
                          onSelected: (_) => saveSetting(
                            context,
                            viewModel.setTimerStyle(option),
                          ),
                        ),
                    ],
                  ),
                ),
                SettingsRow(
                  title: l10n.settingsFocusCompletionCelebrationTitle,
                  subtitle: l10n.settingsFocusCompletionCelebrationSubtitle,
                  onTap: () => saveSetting(
                    context,
                    viewModel.setCelebration(!settings.celebrationEnabled),
                  ),
                  controlWidth: 48,
                  control: ShadSwitch(
                    key: const Key(
                      'settings-focus-completion-celebration-switch',
                    ),
                    value: settings.celebrationEnabled,
                    onChanged: (value) =>
                        saveSetting(context, viewModel.setCelebration(value)),
                  ),
                ),
              ],
            ),
          ],
        );
      case SettingsSection.integrations:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!kIsWeb) ...[
              const GoogleCalendarSettingsScreen(embedded: true),
              const SizedBox(height: 24),
            ],
            if (settings.accountConfigured && settings.signedIn) ...[
              ConnectedAgentsSection(key: ValueKey(settings.userId)),
              const SizedBox(height: 24),
              SettingsRow(
                title: l10n.collaborationInboxTitle,
                subtitle: l10n.collaborationInboxSubtitle,
                onTap: () => showCollaborationInboxDialog(context),
                control: const Icon(LucideIcons.chevronRight, size: 18),
              ),
              const SizedBox(height: 24),
            ],
            if (isCsvTaskImportSupported()) const CsvTaskImportCard(),
          ],
        );
      case SettingsSection.account:
        return _account(ref);
      case SettingsSection.about:
        return const SettingsAppInfoCard(key: Key('settings-app-info-section'));
    }
  }

  Widget _account(WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(settingsViewModelProvider);
    final viewModel = ref.read(settingsViewModelProvider.notifier);
    final returnTo = settingsLocation(SettingsSection.account).toString();
    void retryBootstrap() => unawaited(viewModel.retryAccount());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!state.accountAvailable && state.accountError != null)
          AccountErrorCard(
            key: const Key('account-bootstrap-error'),
            error: state.accountError!,
            retryKey: const Key('account-bootstrap-retry'),
            onRetry: retryBootstrap,
          )
        else if (!state.accountAvailable && state.accountLoading)
          const LinearProgressIndicator()
        else if (!state.accountConfigured)
          AuthUnavailableCard(
            retryKey: const Key('account-unavailable-retry'),
            onRetry: retryBootstrap,
          )
        else ...[
          if (state.accountLoading) const LinearProgressIndicator(minHeight: 2),
          if (state.displayName != null ||
              state.email != null ||
              state.signedIn)
            SettingsRow(
              title: state.displayName ?? state.email ?? l10n.account,
              subtitle: state.email,
              controlWidth: 48,
              control: IconButton(
                tooltip: l10n.settingsRefreshAccount,
                onPressed: state.accountLoading
                    ? null
                    : viewModel.refreshAccount,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
              ),
            )
          else if (!state.accountLoading && state.overviewError == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l10n.loginTitle),
            ),
            PomodoistSignInActions(
              redirectTo: loginRedirectFor(returnTo),
              onSignedIn: () => context.go(returnTo),
            ),
          ],
          if (state.signedIn &&
              (state.displayName != null || state.email != null))
            SettingsRow(
              title: l10n.accountNickname,
              subtitle: state.displayName,
              control: ShadButton.outline(
                key: const Key('account-change-nickname'),
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    animationStyle: AnimationStyle(
                      duration: AppMotion.duration(context, AppMotion.popup),
                      reverseDuration: AppMotion.duration(
                        context,
                        AppMotion.popup,
                      ),
                      curve: AppMotion.curve,
                    ),
                    builder: (_) => AccountNicknameDialog(
                      nickname: state.displayName ?? '',
                      onSave: viewModel.saveNickname,
                    ),
                  );
                },
                child: Text(l10n.accountChangeNickname),
              ),
            ),
          if (state.overviewError != null)
            AccountErrorCard(
              key: const Key('account-overview-error'),
              error: state.overviewError!,
              retryKey: const Key('account-overview-retry'),
              onRetry: viewModel.refreshAccount,
            ),
        ],
        const SizedBox(height: 24),
        const SettingsSubscription(),
        if (state.signedIn) ...[
          const SizedBox(height: 24),
          Divider(height: 1, thickness: 1, color: context.appColors.border),
          Padding(
            key: const Key('account-delete-section'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AccountSignOutButton(
                  key: const Key('account-sign-out-button'),
                  onSignOut:
                      widget.signOutOverride ??
                      () async {
                        await viewModel.signOut();
                      },
                  label: l10n.signOut,
                ),
                ShadButton.ghost(
                  height: 48,
                  key: const Key('account-delete-button'),
                  foregroundColor: context.appColors.error,
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    animationStyle: AnimationStyle(
                      duration: AppMotion.duration(context, AppMotion.popup),
                      reverseDuration: AppMotion.duration(
                        context,
                        AppMotion.popup,
                      ),
                      curve: AppMotion.curve,
                    ),
                    builder: (_) => const AccountDeleteDialog(),
                  ),
                  leading: const Icon(LucideIcons.trash2, size: 18),
                  child: Text(l10n.deleteAccount),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
