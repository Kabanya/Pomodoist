import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';

class ReportsState {
  const ReportsState({
    required this.summary,
    required this.achievements,
    required this.today,
  });
  final AsyncValue<ProductivitySummary> summary;
  final AsyncValue<List<AchievementItem>> achievements;
  final DateTime today;
}

final reportsViewModelProvider =
    NotifierProvider.autoDispose<ReportsViewModel, ReportsState>(
      ReportsViewModel.new,
    );

class ReportsViewModel extends Notifier<ReportsState> {
  @override
  ReportsState build() {
    final clock = ref.watch(clockProvider);
    final today = ref.watch(
      focusTickerProvider.select((tick) {
        final now = (tick.value ?? clock.now()).toLocal();
        return DateTime(now.year, now.month, now.day);
      }),
    );
    return ReportsState(
      summary: ref.watch(productivitySummaryProvider),
      achievements: ref.watch(achievementsProvider),
      today: today,
    );
  }
}

final achievementsViewModelProvider =
    NotifierProvider.autoDispose<
      AchievementsViewModel,
      AsyncValue<List<AchievementItem>>
    >(AchievementsViewModel.new);

class AchievementsViewModel
    extends Notifier<AsyncValue<List<AchievementItem>>> {
  @override
  AsyncValue<List<AchievementItem>> build() => ref.watch(achievementsProvider);
}
