import 'package:app_account/app_account.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final accountClientFixtureProvider = Provider<AccountClient?>(
  (ref) => throw UnimplementedError(),
);

class AccountClientViewModel extends Notifier<int> {
  @override
  int build() => ref.watch(accountClientFixtureProvider).hashCode;
}
