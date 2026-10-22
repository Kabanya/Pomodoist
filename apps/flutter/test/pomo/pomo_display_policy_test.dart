import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/domain/models/pomo/pomo_display_policy.dart';

void main() {
  test('follows only after 500ms on one display; movement resets the wait', () {
    final policy = PomoDisplayPolicy()..placed('a');
    final now = DateTime(2026);
    expect(policy.follow('b', now), isNull);
    expect(
      policy.follow('b', now.add(const Duration(milliseconds: 499))),
      isNull,
    );
    expect(
      policy.follow('a', now.add(const Duration(milliseconds: 500))),
      isNull,
    );
    expect(
      policy.follow('b', now.add(const Duration(milliseconds: 600))),
      isNull,
    );
    expect(
      policy.follow('b', now.add(const Duration(milliseconds: 1100))),
      'b',
    );
  });
  test('interactions cancel pending following and require a new dwell', () {
    final policy = PomoDisplayPolicy()..placed('a');
    final now = DateTime(2026);
    policy.follow('b', now);
    expect(
      policy.follow('b', now.add(const Duration(seconds: 1)), suspended: true),
      isNull,
    );
    expect(policy.follow('b', now.add(const Duration(seconds: 2))), isNull);
    expect(
      policy.follow('b', now.add(const Duration(milliseconds: 2500))),
      'b',
    );
  });
  test(
    'pinned missing display falls back then restores without losing choice',
    () {
      final policy = PomoDisplayPolicy()..placed('a');
      const prefs = PomoPreferences(
        displayMode: PomoDisplayMode.pinned,
        pinnedDisplayId: 'b',
      );
      expect(policy.resolve(['a'], 'a', prefs), 'a');
      expect(policy.resolve(['a', 'b'], 'a', prefs), 'b');
      expect(prefs.pinnedDisplayId, 'b');
    },
  );
  test('manual crossing observes pinned mode and retains stored switch', () {
    final policy = PomoDisplayPolicy()..placed('a');
    expect(policy.dragTarget('b', const PomoPreferences()), 'b');
    expect(
      policy.dragTarget(
        'b',
        const PomoPreferences(allowCrossDisplayDrag: false),
      ),
      'a',
    );
    expect(
      policy.dragTarget(
        'b',
        const PomoPreferences(
          displayMode: PomoDisplayMode.pinned,
          pinnedDisplayId: 'a',
        ),
      ),
      'a',
    );
  });
  test('unknown user display and disappeared monitor resolve to primary', () {
    final policy = PomoDisplayPolicy()..placed('removed');
    expect(policy.resolve(['a'], 'a', const PomoPreferences()), 'a');
    expect(policy.follow(null, DateTime(2026)), isNull);
    policy.clear();
    expect(policy.currentDisplayId, isNull);
  });
  test(
    'suspension cancels queued following but preserves explicit dragging',
    () {
      final policy = PomoDisplayPolicy()..placed('a');
      final now = DateTime(2026);
      policy.follow('b', now);
      policy.follow('b', now.add(const Duration(milliseconds: 500)));
      policy.follow(
        'b',
        now.add(const Duration(milliseconds: 501)),
        suspended: true,
      );
      expect(policy.resolve(['a', 'b'], 'a', const PomoPreferences()), 'a');
      policy.request('b');
      policy.follow('b', now.add(const Duration(seconds: 1)), suspended: true);
      expect(policy.resolve(['a', 'b'], 'a', const PomoPreferences()), 'b');
    },
  );
}
