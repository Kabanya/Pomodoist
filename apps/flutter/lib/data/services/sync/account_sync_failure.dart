/// Some stages committed while another stage needs retrying.
class AccountSyncPartialFailure implements Exception {
  const AccountSyncPartialFailure(this.entityTypes, this.cause);
  final Set<String> entityTypes;
  final Object cause;
  @override
  String toString() => 'Synchronization is incomplete.';
}
