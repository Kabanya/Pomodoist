import 'package:flutter/widgets.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:pomodoist/l10n/app_localizations_en.dart';

extension AppL10nContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();
}
