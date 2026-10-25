/// Confirmation is bound to both the account and the exact archived contents.
class LegacyRecoveryRequest {
  const LegacyRecoveryRequest({
    required this.userId,
    required this.fingerprint,
    required this.recordCount,
  });
  final String userId;
  final String fingerprint;
  final int recordCount;
}
