import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_l10n.dart';
import '../../../../app/account_providers.dart';
import '../../../../app/formatters.dart';
import '../../../../app/providers.dart';
import '../../../../app/theme/app_theme.dart';
import '../data/google_calendar_api_client.dart';
import '../data/google_calendar_config.dart';
import 'google_calendar_web_sign_in_button.dart';

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
  void initState() {
    super.initState();
    unawaited(
      ref.read(googleCalendarAuthServiceProvider).initialize().catchError((_) {
        // The connect/sync action reports configuration errors in the UI.
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final connection = ref.watch(googleCalendarConnectionProvider);
    final localDeviceId = ref.watch(pomodoistDeviceIdProvider).value;
    final child = connection.when(
      data: (row) {
        final connected =
            row?.calendarId != null && row?.status != 'disconnected';
        final connectedElsewhere =
            connected &&
            row?.ownerDeviceId != null &&
            localDeviceId != null &&
            row!.ownerDeviceId != localDeviceId;
        final children = [
          Text(
            l10n.googleCalendarTitle,
            style: widget.embedded
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            connectedElsewhere
                ? l10n.googleCalendarConnectedOnAnotherDeviceSubtitle
                : connected
                ? l10n.googleCalendarConnectedSubtitle
                : l10n.googleCalendarDisconnectedSubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: 20),
          if (!connected && kIsWeb) ...[
            const GoogleCalendarWebSignInButton(),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy || (connected && localDeviceId == null)
                    ? null
                    : connectedElsewhere
                    ? () => _connect()
                    : connected
                    ? () => _sync()
                    : () => _connect(),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        connectedElsewhere
                            ? Icons.phonelink_setup
                            : connected
                            ? Icons.sync
                            : Icons.link,
                      ),
                label: Text(
                  connectedElsewhere
                      ? l10n.useThisDevice
                      : connected
                      ? l10n.syncNow
                      : l10n.connect,
                ),
              ),
              if (connected && !connectedElsewhere)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _disconnect(),
                  icon: const Icon(Icons.link_off),
                  label: Text(l10n.disconnect),
                ),
            ],
          ),
          const SizedBox(height: 24),
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
        if (widget.embedded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
        }
        return ListView(padding: const EdgeInsets.all(20), children: children);
      },
      loading: () => widget.embedded
          ? const LinearProgressIndicator(minHeight: 2)
          : const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => widget.embedded
          ? Text(l10n.failedToLoadIntegration(error))
          : Center(child: Text(l10n.failedToLoadIntegration(error))),
    );
    return widget.embedded ? child : SafeArea(child: child);
  }

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
  final l10n = context.l10n;
  if (error is GoogleCalendarConfigException) {
    return error.message;
  }
  if (error is GoogleCalendarAuthRequiredException) {
    return l10n.googleAuthRequired;
  }
  if (error is PlatformException &&
      error.code == 'google_sign_in' &&
      (error.message?.contains('No active configuration') ?? false)) {
    return l10n.googleSignInNotConfigured;
  }
  if (error is PlatformException &&
      error.code == 'google_sign_in' &&
      ((error.message?.contains('URL scheme') ?? false) ||
          (error.message?.contains('CFBundleURLSchemes') ?? false))) {
    return l10n.googleCallbackNotConfigured;
  }
  final text = error.toString();
  if (text.contains('official Google web sign-in button')) {
    return l10n.googleWebButtonFirst;
  }
  if (text.contains('access_denied') ||
      text.contains('not completed the Google verification process')) {
    return l10n.googleAccessDenied;
  }
  return error.toString();
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
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    row.$1,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    row.$2,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        if (warning != null && warning!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _MessageBand(
            icon: Icons.warning_amber_outlined,
            text: warning!,
            color: colors.warning,
          ),
        ],
        if (lastError != null && lastError!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _MessageBand(
            icon: Icons.error_outline,
            text: lastError!,
            color: colors.accent,
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
