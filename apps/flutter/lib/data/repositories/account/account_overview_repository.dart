import 'package:app_account/app_account.dart';

import 'package:pomodoist/data/services/account/account_overview_service.dart';
import 'package:pomodoist/domain/models/account/account_overview.dart';

/// Owns account overview loading and the related install registration.
final class AccountOverviewRepository {
  const AccountOverviewRepository(this._account);

  final AccountClient _account;

  Future<PomodoistAccountOverview> load({
    Future<String> Function()? deviceId,
    required Duration timeout,
  }) => AccountOverviewService(
    _account,
  ).load(deviceId: deviceId, timeout: timeout);
}
