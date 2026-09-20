import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:app_account/app_account.dart';

import 'package:pomodoist/domain/models/account/account_overview.dart';

final class AccountOverviewService {
  const AccountOverviewService(this._account);

  final AccountClient _account;

  Future<PomodoistAccountOverview> load({
    Future<String> Function()? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (deviceId != null) unawaited(_registerInstall(deviceId, timeout));
    return map(await _account.getOverview().timeout(timeout));
  }

  Future<void> _registerInstall(
    Future<String> Function() deviceId,
    Duration timeout,
  ) async {
    final userId = _account.currentUserId;
    try {
      final info = await PackageInfo.fromPlatform().timeout(timeout);
      final id = await deviceId().timeout(timeout);
      if (userId == null || _account.currentUserId != userId) return;
      await _account
          .registerInstall(
            appId: AccountAppId.pomodoist,
            deviceId: id,
            platform: kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
            appVersion: info.buildNumber.isEmpty
                ? info.version
                : '${info.version}+${info.buildNumber}',
          )
          .timeout(timeout);
    } on Object {
      // Install registration is advisory and must never block the profile.
    }
  }

  static PomodoistAccountOverview map(AccountOverview overview) =>
      PomodoistAccountOverview(
        profile: PomodoistAccountProfile(
          id: overview.profile.id,
          email: overview.profile.email,
          displayName: overview.profile.displayName,
          isPro: overview.profile.pomodoistIsPro,
        ),
        apps: [
          for (final app in overview.apps)
            PomodoistAccountAppSummary(
              id: app.id,
              displayName: app.displayName,
              entitlements: [
                for (final entitlement in app.entitlements)
                  PomodoistAccountEntitlement(
                    appId: entitlement.appId,
                    entitlementId: entitlement.entitlementId,
                    status: entitlement.status,
                    purchaseType: entitlement.purchaseType,
                    source: entitlement.source,
                    productId: entitlement.productId,
                    store: entitlement.store,
                    validUntil: entitlement.validUntil,
                    renewsAt: entitlement.renewsAt,
                  ),
              ],
            ),
        ],
        generatedAt: overview.generatedAt,
      );
}
