import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/sync/pomodoist_retention.dart';
import 'package:pomodoist/features/collaboration/domain/collaboration_models.dart';

void main() {
  test(
    'personal free history is 365 days with an exact nonextending grace deadline',
    () {
      final now = DateTime.utc(2026, 9, 14);
      expect(
        pomodoistTaskHistoryCutoff(null, now: now),
        DateTime.utc(2025, 9, 14),
      );
      final deadline = now.add(const Duration(days: 30));
      expect(
        pomodoistTaskHistoryCutoff(null, now: now, graceEndsAt: deadline),
        isNull,
      );
      expect(
        pomodoistTaskHistoryCutoff(null, now: deadline, graceEndsAt: deadline),
        deadline.subtract(const Duration(days: 365)),
      );
      expect(
        pomodoistTaskHistoryCutoff(null, now: deadline, historyUnlimited: true),
        isNull,
      );
    },
  );

  test('an observer cannot edit or upload even with Pro', () {
    final scope = SharedScope.fromJson({
      'id': 'shared',
      'rootProjectId': 'root',
      'ownerId': 'owner',
      'role': 'observer',
    });
    expect(scope.canEdit, isFalse);
    expect(scope.canManage, isFalse);
    expect(scope.canDeleteRoot('observer'), isFalse);
  });

  test('administrators cannot delete another owners root', () {
    final scope = SharedScope.fromJson({
      'id': 'shared',
      'rootProjectId': 'root',
      'ownerId': 'owner',
      'role': 'administrator',
    });
    expect(scope.canEdit, isTrue);
    expect(scope.canManage, isTrue);
    expect(scope.canDeleteRoot('administrator'), isFalse);
    expect(scope.canDeleteRoot('owner'), isTrue);
  });

  test('history grace expires at the exact server deadline', () {
    final scope = SharedScope.fromJson({
      'id': 'shared',
      'rootProjectId': 'root',
      'ownerId': 'owner',
      'role': 'member',
      'historyUnlimited': false,
      'graceEndsAt': '2026-10-14T00:00:00Z',
    });
    expect(scope.historyCutoff(DateTime.utc(2026, 10, 13)), isNull);
    expect(
      scope.historyCutoff(DateTime.utc(2026, 10, 14)),
      DateTime.utc(2025, 10, 14),
    );
  });
}
