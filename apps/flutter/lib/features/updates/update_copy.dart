import 'package:flutter/widgets.dart';

import '../../app/config/app_l10n.dart';
import '../../l10n/app_localizations.dart';
import 'update_contracts.dart';

class UpdateCopy {
  const UpdateCopy(this.l10n);
  factory UpdateCopy.of(BuildContext context) => UpdateCopy(context.l10n);

  final AppLocalizations l10n;
  String get title => l10n.updateTitle;
  String get update => l10n.updateAction;
  String get close => l10n.commonClose;
  String get check => l10n.updateCheck;
  String get settings => l10n.updateSettings;
  String get rc => l10n.updateReceiveRc;
  String get stable => l10n.updateStableChannel;
  String get rcChannel => l10n.updateRcChannel;
  String get rcHelp => l10n.updateRcHelp;
  String get restart => l10n.updateRestart;
  String get notes => l10n.updateNotes;
  String get ownerManaged => l10n.updateOwnerManaged;
  String get unsupported => l10n.updateUnsupported;
  String version(String value) => l10n.updateVersion(value);
  String phase(UpdatePhase value) => switch (value) {
    UpdatePhase.idle => l10n.updatePhaseIdle,
    UpdatePhase.checking => l10n.updatePhaseChecking,
    UpdatePhase.available => l10n.updatePhaseAvailable,
    UpdatePhase.downloading => l10n.updatePhaseDownloading,
    UpdatePhase.verifying => l10n.updatePhaseVerifying,
    UpdatePhase.installing => l10n.updatePhaseInstalling,
    UpdatePhase.upToDate => l10n.updatePhaseUpToDate,
    UpdatePhase.failed => l10n.updatePhaseFailed,
  };
}
