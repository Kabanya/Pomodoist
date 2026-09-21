import 'package:pomodoist/data/repositories/achievements/achievement_repository.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

/// Configurable [AchievementRepository] double.
///
/// Every method has a working default, so a test only has to set the fields it
/// cares about. Calls are appended to the matching recording list, and a
/// `Result`-returning method returns its `<method>Error` failure when that field
/// is non-null.
class FakeAchievementRepository extends StrictFake
    implements AchievementRepository {
  /// Achievements emitted by [watchAchievements].
  List<AchievementItem> achievements = const [];

  /// Announcements [takePendingAnnouncements] succeeds with.
  List<AchievementItem> pendingAnnouncements = const [];

  Object? takePendingAnnouncementsError;

  final watchAchievementsCalls = <void>[];
  final takePendingAnnouncementsCalls = <List<AchievementItem>>[];

  @override
  Stream<List<AchievementItem>> watchAchievements() {
    watchAchievementsCalls.add(null);
    return Stream.value(achievements);
  }

  @override
  Future<Result<List<AchievementItem>>> takePendingAnnouncements(
    List<AchievementItem> items,
  ) async {
    takePendingAnnouncementsCalls.add(items);
    final error = takePendingAnnouncementsError;
    if (error != null) {
      return Result.error(error, StackTrace.current);
    }
    return Result.ok(pendingAnnouncements);
  }
}
