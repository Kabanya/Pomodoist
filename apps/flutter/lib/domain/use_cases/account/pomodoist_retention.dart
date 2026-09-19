import 'package:pomodoist/domain/models/account/account_overview.dart';

const pomodoistFreeTaskHistoryRetention = Duration(days: 365);

bool hasActivePomodoistPaidEntitlement(
  PomodoistAccountOverview? overview, {
  DateTime? now,
  bool hasLocalPaidEntitlement = false,
}) => hasLocalPaidEntitlement || (overview?.profile.isPro ?? false);

PomodoistAccountEntitlement? activePomodoistPaidEntitlement(
  PomodoistAccountOverview? overview, {
  DateTime? now,
}) {
  final utcNow = (now ?? DateTime.now()).toUtc();
  for (final entitlement
      in overview?.entitlements ?? const <PomodoistAccountEntitlement>[]) {
    if (entitlement.appId != pomodoistAccountAppId ||
        !entitlement.active ||
        !entitlement.paid) {
      continue;
    }
    final validUntil = entitlement.validUntil;
    if (validUntil == null || validUntil.toUtc().isAfter(utcNow)) {
      return entitlement;
    }
  }
  return null;
}

DateTime? pomodoistTaskHistoryCutoff(
  PomodoistAccountOverview? overview, {
  DateTime? now,
  DateTime? graceEndsAt,
  bool historyUnlimited = false,
  bool hasLocalPaidEntitlement = false,
}) {
  final utcNow = (now ?? DateTime.now()).toUtc();
  if (historyUnlimited || (graceEndsAt?.toUtc().isAfter(utcNow) ?? false)) {
    return null;
  }
  if (hasActivePomodoistPaidEntitlement(
    overview,
    hasLocalPaidEntitlement: hasLocalPaidEntitlement,
  )) {
    return null;
  }
  return utcNow.subtract(pomodoistFreeTaskHistoryRetention);
}
