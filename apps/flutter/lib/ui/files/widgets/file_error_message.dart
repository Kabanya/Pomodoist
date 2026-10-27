import 'package:pomodoist/domain/models/files/file_attachment.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';

String fileErrorMessage(AppLocalizations l10n, Object? error) =>
    switch (error is FileFailure ? error.code : null) {
      'pro_required' => l10n.filesProRequired,
      'read_only' || 'forbidden' || '42501' => l10n.filesReadOnly,
      'file_too_large' => l10n.filesTooLarge,
      '54000' ||
      'quota_exceeded' ||
      'monthly_quota_exceeded' ||
      'yearly_quota_exceeded' => l10n.filesQuotaExceeded,
      'session_changed' || 'unauthorized' => l10n.filesSignIn,
      _ => l10n.filesUnavailable,
    };
