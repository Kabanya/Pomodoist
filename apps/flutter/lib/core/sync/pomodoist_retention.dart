import 'package:app_account/app_account.dart';

const pomodoistFreeTaskHistoryRetention = Duration(days: 365);

bool hasActivePomodoistPaidEntitlement(
  AccountOverview? overview, {
  DateTime? now,
  bool hasLocalPaidEntitlement = false,
}) {
  if (hasLocalPaidEntitlement) {
    return true;
  }
  return overview?.profile.pomodoistIsPro ?? false;
}

AccountEntitlement? activePomodoistPaidEntitlement(
  AccountOverview? overview, {
  DateTime? now,
}) {
  final utcNow = (now ?? DateTime.now()).toUtc();
  for (final app in overview?.apps ?? const <AccountAppSummary>[]) {
    if (app.id != AccountAppId.pomodoist) {
      continue;
    }
    for (final entitlement in app.entitlements) {
      if (!entitlement.active ||
          !(entitlement.subscription || entitlement.lifetime)) {
        continue;
      }
      final validUntil = entitlement.validUntil;
      if (validUntil == null || validUntil.toUtc().isAfter(utcNow)) {
        return entitlement;
      }
    }
  }
  return null;
}

DateTime? pomodoistTaskHistoryCutoff(
  AccountOverview? overview, {
  DateTime? now,
  DateTime? graceEndsAt,
  bool historyUnlimited = false,
  bool hasLocalPaidEntitlement = false,
}) {
  if (historyUnlimited ||
      (graceEndsAt?.toUtc().isAfter((now ?? DateTime.now()).toUtc()) ?? false))
    return null;
  if (hasActivePomodoistPaidEntitlement(
    overview,
    now: now,
    hasLocalPaidEntitlement: hasLocalPaidEntitlement,
  )) {
    return null;
  }
  return (now ?? DateTime.now()).toUtc().subtract(
    pomodoistFreeTaskHistoryRetention,
  );
}
