import 'package:app_account/app_account.dart';

import 'package:pomodoist/domain/models/account/account_overview.dart';

final class AccountOverviewService {
  const AccountOverviewService(this._account);

  final AccountClient _account;

  Future<PomodoistAccountOverview> load() async =>
      map(await _account.getOverview());

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
