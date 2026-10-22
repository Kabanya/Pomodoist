import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';

void main() {
  test('legacy and malformed display preferences use safe defaults', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {
        'displayMode': 'future',
        'allowCrossDisplayDrag': 'false',
        'pinnedDisplayId': 123,
        'displayPositions': [],
      },
    ]) {
      final prefs = PomoPreferences.fromJson(json);
      expect(prefs.displayMode, PomoDisplayMode.followUser);
      expect(prefs.allowCrossDisplayDrag, isTrue);
      expect(prefs.pinnedDisplayId, isNull);
      expect(prefs.displayPositions, isEmpty);
    }
  });
  test('display positions reject partial, nonnumeric and nonfinite values', () {
    final prefs = PomoPreferences.fromJson({
      'displayPositions': {
        'left': {'x': -123.5, 'y': 42},
        'partial': {'x': 12},
        'string': {'x': '12', 'y': 3},
        'nan': {'x': double.nan, 'y': 3},
        'infinite': {'x': 1, 'y': double.infinity},
        'list': [1, 2],
      },
    });
    expect(prefs.displayPositions.keys, ['left']);
    expect(prefs.displayPositions['left']!.x, -123.5);
    expect(prefs.displayPositions['left']!.y, 42);
  });
  test('display settings round trip through persisted JSON', () {
    final original = const PomoPreferences().copyWith(
      displayMode: PomoDisplayMode.pinned,
      allowCrossDisplayDrag: false,
      pinnedDisplayId: 'HDMI-1',
      displayPositions: {
        'HDMI-1': const PomoDisplayPosition(x: 12.5, y: 34),
        'DP-1': const PomoDisplayPosition(x: 67, y: 89.5),
      },
    );
    final restored = PomoPreferences.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.displayMode, PomoDisplayMode.pinned);
    expect(restored.allowCrossDisplayDrag, isFalse);
    expect(restored.pinnedDisplayId, 'HDMI-1');
    expect(restored.toJson(), original.toJson());
    final updated = restored.copyWith(quiet: true);
    expect(updated.displayMode, restored.displayMode);
    expect(updated.allowCrossDisplayDrag, isFalse);
    expect(updated.pinnedDisplayId, 'HDMI-1');
    expect(updated.displayPositions['DP-1']!.y, 89.5);
  });
  test(
    'reset clears positions while preserving monitor policy and selection',
    () {
      final reset = const PomoPreferences(
        displayMode: PomoDisplayMode.pinned,
        allowCrossDisplayDrag: true,
        pinnedDisplayId: 'DP-1',
        displayId: 'HDMI-1',
        x: 120,
        y: 230,
        displayPositions: {'DP-1': PomoDisplayPosition(x: 11, y: 22)},
      ).copyWith(resetPosition: true);
      expect(reset.x, isNull);
      expect(reset.y, isNull);
      expect(reset.displayId, isNull);
      expect(reset.displayPositions, isEmpty);
      expect(reset.displayMode, PomoDisplayMode.pinned);
      expect(reset.pinnedDisplayId, 'DP-1');
      expect(reset.allowCrossDisplayDrag, isTrue);
    },
  );
  test('switching display mode retains the cross-display drag preference', () {
    final prefs = const PomoPreferences(allowCrossDisplayDrag: false)
        .copyWith(displayMode: PomoDisplayMode.pinned)
        .copyWith(displayMode: PomoDisplayMode.followUser);
    expect(prefs.allowCrossDisplayDrag, isFalse);
  });
}
