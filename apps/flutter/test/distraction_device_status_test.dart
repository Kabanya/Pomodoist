import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/distractions/view_models/distraction_view_model.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);
  final device = <String, dynamic>{
    'lastSeenAt': now.subtract(const Duration(seconds: 10)).toIso8601String(),
    'appliedRevision': 4,
    'capabilities': {'websiteApplied': true},
  };

  test('connected Chrome needs confirmed rules for the current revision', () {
    expect(distractionDeviceStatus(device, revision: 4, now: now), (
      connected: true,
      applied: true,
    ));
    for (final revision in [null, 3, 5]) {
      expect(distractionDeviceStatus(device, revision: revision, now: now), (
        connected: true,
        applied: false,
      ));
    }
    for (final capabilities in [
      null,
      'invalid',
      {},
      {'websiteBlocking': true},
    ]) {
      expect(
        distractionDeviceStatus(
          {...device, 'capabilities': capabilities},
          revision: 4,
          now: now,
        ),
        (connected: true, applied: false),
      );
    }
  });

  test('stale, missing or future confirmations cannot enable protection', () {
    for (final seen in [
      null,
      'invalid',
      now.subtract(const Duration(seconds: 45)).toIso8601String(),
      now.add(const Duration(seconds: 1)).toIso8601String(),
    ]) {
      expect(
        distractionDeviceStatus(
          {...device, 'lastSeenAt': seen},
          revision: 4,
          now: now,
        ),
        (connected: false, applied: false),
      );
    }
  });

  test('detached device stays connected but protection is disabled', () {
    expect(
      distractionDeviceStatus(
        {...device, 'detached': true},
        revision: 4,
        now: now,
      ),
      (connected: true, applied: false),
    );
    expect(
      distractionDeviceStatus(
        {
          ...device,
          'capabilities': {'nativeApplied': true},
        },
        revision: 4,
        now: now,
      ),
      (connected: true, applied: true),
    );
  });
}
