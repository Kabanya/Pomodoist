import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../../app/app_l10n.dart';
import '../../../settings/presentation/settings_components.dart';
import '../../../../app/account_providers.dart';
import '../../../../app/formatters.dart';
import '../../../../app/providers.dart';
import '../../../../app/theme/app_theme.dart';
import '../data/google_calendar_sync_controller.dart';

class GoogleCalendarSettingsScreen extends ConsumerStatefulWidget {
  const GoogleCalendarSettingsScreen({this.embedded = false, super.key});

  final bool embedded;

  @override
  ConsumerState<GoogleCalendarSettingsScreen> createState() =>
      _GoogleCalendarSettingsScreenState();
}

class _GoogleCalendarSettingsScreenState
    extends ConsumerState<GoogleCalendarSettingsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connection = ref.watch(googleCalendarConnectionProvider);
    final child = connection.when(
      skipError: true,
      skipLoadingOnReload: true,
      data: (row) {
        final connected =
            row?.calendarId != null && row?.status != 'disconnected';
        final children = [
          if (connection.isLoading) const LinearProgressIndicator(minHeight: 2),
          if (connection.hasError) _loadError(connection.error!),
          SettingsRow(
            title: l10n.googleCalendarTitle,
            subtitle: connected
                ? l10n.googleCalendarConnectedSubtitle
                : l10n.googleCalendarDisconnectedSubtitle,
            control: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ShadButton(
                  height: 48,
                  enabled: !_busy,
                  onPressed: _busy
                      ? null
                      : connected
                      ? () => _sync()
                      : () => _connect(),
                  leading: _busy
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Icon(
                          connected ? LucideIcons.refreshCw : LucideIcons.link2,
                        ),
                  child: Text(connected ? l10n.syncNow : l10n.connect),
                ),
                if (connected)
                  ShadButton.outline(
                    height: 48,
                    enabled: !_busy,
                    onPressed: _busy ? null : () => _disconnect(),
                    leading: const Icon(LucideIcons.unlink),
                    child: Text(l10n.disconnect),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StatusRows(
            accountEmail: row?.accountEmail,
            calendarName: row?.calendarName,
            calendarId: row?.calendarId,
            status: row?.status ?? 'disconnected',
            lastSyncFinishedAt: row?.lastSyncFinishedAt,
            lastError: row?.lastError,
            warning: row?.warning,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
      loading: () => widget.embedded
          ? const LinearProgressIndicator(minHeight: 2)
          : const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _loadError(error),
    );
    return widget.embedded
        ? child
        : SettingsSurface(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ShadButton.ghost(
                    height: 48,
                    leading: const Icon(LucideIcons.arrowLeft, size: 18),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/settings?section=integrations');
                      }
                    },
                    child: Text(l10n.settingsSectionIntegrations),
                  ),
                ),
                const SizedBox(height: 24),
                child,
              ],
            ),
          );
  }

  Widget _loadError(Object error) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.failedToLoadIntegration(error),
        style: TextStyle(color: context.appColors.error),
      ),
      ShadButton.ghost(
        height: 48,
        onPressed: () => ref.invalidate(googleCalendarConnectionProvider),
        child: Text(context.l10n.commonRetry),
      ),
    ],
  );

  Future<void> _connect() async {
    await _run(() => ref.read(googleCalendarSyncControllerProvider).connect());
  }

  Future<void> _sync() async {
    await _run(
      () => ref
          .read(googleCalendarSyncControllerProvider)
          .syncNow(interactive: true),
    );
  }

  Future<void> _disconnect() async {
    await _run(
      () => ref.read(googleCalendarSyncControllerProvider).disconnect(),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.googleCalendarFailed(
                _googleCalendarErrorMessage(context, error),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

String _googleCalendarErrorMessage(BuildContext context, Object error) {
  if (error is GoogleCalendarServerException) return error.message;
  return context.l10n.authServiceUnavailable;
}

class _StatusRows extends StatelessWidget {
  const _StatusRows({
    required this.status,
    this.accountEmail,
    this.calendarName,
    this.calendarId,
    this.lastSyncFinishedAt,
    this.lastError,
    this.warning,
  });

  final String? accountEmail;
  final String? calendarName;
  final String? calendarId;
  final String status;
  final DateTime? lastSyncFinishedAt;
  final String? lastError;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final rows = [
      (l10n.status, status),
      (l10n.account, accountEmail ?? l10n.notConnected),
      (l10n.calendar, calendarName ?? 'Pomodoist'),
      (l10n.calendarId, calendarId ?? l10n.notCreated),
      (
        l10n.lastSync,
        lastSyncFinishedAt == null
            ? l10n.never
            : formatLocalDate(context, lastSyncFinishedAt!.toLocal()),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          children: [
            for (final row in rows)
              SettingsRow(
                title: row.$1,
                control: SelectableText(
                  row.$2,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],
        ),
        if (warning != null && warning!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _MessageBand(
            icon: LucideIcons.triangleAlert,
            text: warning!,
            color: colors.warning,
          ),
        ],
        if (lastError != null && lastError!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _MessageBand(
            icon: LucideIcons.circleAlert,
            text: lastError!,
            color: colors.error,
          ),
        ],
      ],
    );
  }
}

class _MessageBand extends StatelessWidget {
  const _MessageBand({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
