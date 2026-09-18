import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadSwitch, ShadSelect, ShadOption;

import '../../../app/config/account_providers.dart';
import '../../../app/config/runtime_public_config.dart';
import '../../../app/config/app_language.dart';
import '../../../app/config/app_l10n.dart';
import '../../../app/config/providers.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../focus/presentation/focus_view_mode.dart';
import '../../integrations/google_calendar/presentation/google_calendar_settings_screen.dart';
import '../../voice/data/voice_transcription_mode.dart';
import 'settings_components.dart';
import 'settings_navigation.dart';
import '../../collaboration/presentation/collaboration_inbox_dialog.dart';
import 'settings_subscription.dart';
import 'account_sign_out_button.dart';
import 'account_nickname_dialog.dart';
import 'app_info_card.dart';
import 'csv_task_import_card.dart';
import 'theme_settings_card.dart';
import 'voice_transcription_settings_card.dart';
import 'pomodoist_account_actions.dart';
import 'auth_surfaces.dart';
import 'account_delete_dialog.dart';
import 'connected_agents_section.dart';
import 'task_list_settings.dart';
export 'login_screen.dart';
export 'register_screen.dart';

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
    if (!ref.read(connectedAgentsProvider).isLoading) {
      unawaited(
        Future<void>.microtask(() {
          if (mounted) {
            return ref.read(connectedAgentsProvider.notifier).refresh();
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
    switch (section) {
      case SettingsSection.general:
        ref.watch(accountAuthStateProvider);
        final language = ref.watch(appLanguageProvider);
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
                    saveSetting(
                      context,
                      ref.read(appLanguageProvider.notifier).setLanguage(value),
                    );
                  }
                },
              ),
            ),
            if (supportsVoiceTranscriptionModeSelection(
              isWeb: kIsWeb,
              platform: defaultTargetPlatform,
            ))
              VoiceTranscriptionSettingsCard(
                signedIn:
                    ref.watch(accountClientProvider)?.currentUserId != null,
              ),
            SettingsRow(
              title: l10n.settingsReturnRemindersTitle,
              subtitle: l10n.settingsReturnRemindersSubtitle,
              onTap: () => saveSetting(
                context,
                ref
                    .read(reengagementNotificationsEnabledProvider.notifier)
                    .setEnabled(
                      !ref.read(reengagementNotificationsEnabledProvider),
                    ),
              ),
              controlWidth: 48,
              control: ShadSwitch(
                key: const Key('settings-reengagement-notifications-switch'),
                value: ref.watch(reengagementNotificationsEnabledProvider),
                onChanged: (value) => saveSetting(
                  context,
                  ref
                      .read(reengagementNotificationsEnabledProvider.notifier)
                      .setEnabled(value),
                ),
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
            TaskListStyleSettings(),
          ],
        );
      case SettingsSection.tasksFocus:
        final style = ref.watch(focusTimerVisualStyleProvider);
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
                            ref
                                .read(focusTimerVisualStyleProvider.notifier)
                                .setStyle(option),
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
                    ref
                        .read(
                          focusCompletionCelebrationEnabledProvider.notifier,
                        )
                        .setEnabled(
                          !ref.read(focusCompletionCelebrationEnabledProvider),
                        ),
                  ),
                  controlWidth: 48,
                  control: ShadSwitch(
                    key: const Key(
                      'settings-focus-completion-celebration-switch',
                    ),
                    value: ref.watch(focusCompletionCelebrationEnabledProvider),
                    onChanged: (value) => saveSetting(
                      context,
                      ref
                          .read(
                            focusCompletionCelebrationEnabledProvider.notifier,
                          )
                          .setEnabled(value),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case SettingsSection.integrations:
        ref.watch(accountAuthStateProvider);
        final account = ref.watch(accountClientProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!kIsWeb) ...[
              const GoogleCalendarSettingsScreen(embedded: true),
              const SizedBox(height: 24),
            ],
            if (ref.watch(accountConfiguredProvider) &&
                account?.currentUserId != null) ...[
              ConnectedAgentsSection(
                key: ValueKey(account!.currentUserId),
                account: account,
              ),
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
    ref.watch(accountAuthStateProvider);
    final account = ref.watch(accountClientProvider);
    final bootstrap = ref.watch(accountBootstrapProvider);
    final overview = ref.watch(accountOverviewProvider);
    final configured = ref.watch(accountConfiguredProvider);
    final signedIn = account?.currentUserId != null;
    final profile = overview.value?.profile;
    final returnTo = settingsLocation(SettingsSection.account).toString();
    void retryBootstrap() => unawaited(
      ref
          .read(accountBootstrapProvider.notifier)
          .retry()
          .whenComplete(() => ref.invalidate(accountOverviewProvider)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (account == null && bootstrap.hasError)
          AccountErrorCard(
            key: const Key('account-bootstrap-error'),
            error: bootstrap.error!,
            retryKey: const Key('account-bootstrap-retry'),
            onRetry: retryBootstrap,
          )
        else if (account == null && bootstrap.isLoading)
          const LinearProgressIndicator()
        else if (!configured)
          AuthUnavailableCard(
            retryKey: const Key('account-unavailable-retry'),
            onRetry: retryBootstrap,
          )
        else ...[
          if (overview.isLoading) const LinearProgressIndicator(minHeight: 2),
          if (profile != null || signedIn)
            SettingsRow(
              title: profile?.displayName ?? profile?.email ?? l10n.account,
              subtitle: profile?.email,
              controlWidth: 48,
              control: IconButton(
                tooltip: l10n.settingsRefreshAccount,
                onPressed: overview.isLoading
                    ? null
                    : () => ref.invalidate(accountOverviewProvider),
                icon: const Icon(LucideIcons.refreshCw, size: 18),
              ),
            )
          else if (!overview.isLoading && !overview.hasError) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l10n.loginTitle),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: pomodoistAccountSignInActions(
                context: context,
                account: account,
                redirectTo: loginRedirectFor(returnTo),
                onSignedIn: () => context.go(returnTo),
                config: ref.read(runtimePublicConfigProvider),
                nativeCaptchaCallbacks: ref
                    .read(nativeLinkCoordinatorProvider)
                    ?.captchaCallbacks,
                appleLabel: l10n.accountApple,
                googleLabel: l10n.accountGoogle,
                emailLabel: l10n.accountEmail,
              ),
            ),
          ],
          if (signedIn && profile != null)
            SettingsRow(
              title: l10n.accountNickname,
              subtitle: profile.displayName,
              control: ShadButton.outline(
                key: const Key('account-change-nickname'),
                onPressed: () {
                  final userId = account!.currentUserId!;
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
                      nickname: profile.displayName ?? '',
                      onSave: (name) async {
                        await updateAccountNickname(
                          Supabase.instance.client,
                          userId,
                          name,
                        ).timeout(ref.read(accountRequestTimeoutProvider));
                        if (context.mounted) {
                          ref.invalidate(accountOverviewProvider);
                        }
                      },
                    ),
                  );
                },
                child: Text(l10n.accountChangeNickname),
              ),
            ),
          if (overview.hasError)
            AccountErrorCard(
              key: const Key('account-overview-error'),
              error: overview.error!,
              retryKey: const Key('account-overview-retry'),
              onRetry: () => ref.invalidate(accountOverviewProvider),
            ),
        ],
        const SizedBox(height: 24),
        const SettingsSubscription(),
        if (signedIn) ...[
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
                        await account?.signOut();
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
                    builder: (_) => AccountDeleteDialog(account: account!),
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
