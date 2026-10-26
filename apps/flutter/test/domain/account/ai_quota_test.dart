import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/account/ai_quota.dart';

void main() {
  test('quota uses server values and clamps remaining', () {
    final quota = AiQuota.fromJson({
      'used': 1001,
      'limit': 1000,
      'resetsAt': '2026-11-01T00:00:00Z',
    });
    expect(quota.remaining, 0);
    expect(quota.resetsAt.isUtc, true);
    expect(
      () => AiQuota.fromJson({'used': -1, 'limit': 1000}),
      throwsFormatException,
    );
  });
}
