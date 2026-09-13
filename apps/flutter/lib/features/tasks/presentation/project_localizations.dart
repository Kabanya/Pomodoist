import '../../../l10n/app_localizations.dart';
import '../domain/task_models.dart';

extension ProjectLocalizations on ProjectItem {
  String displayName(AppLocalizations l10n) =>
      id == inboxProjectId && name == 'Inbox' ? l10n.navInbox : name;
}
