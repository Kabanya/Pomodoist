import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';
import 'package:pomodoist/domain/models/productivity/productivity_models.dart';

enum ReportsProjectPeriod { today, lastSevenDays }

class ReportsState {
  const ReportsState({
    required this.summary,
    required this.achievements,
    required this.today,
    this.projectPeriod = ReportsProjectPeriod.lastSevenDays,
    this.expandedProjectIds = const {},
  });
  final AsyncValue<ProductivitySummary> summary;
  final AsyncValue<List<AchievementItem>> achievements;
  final DateTime today;
  final ReportsProjectPeriod projectPeriod;
  final Set<String?> expandedProjectIds;
}

final reportsViewModelProvider =
    NotifierProvider.autoDispose<ReportsViewModel, ReportsState>(
      ReportsViewModel.new,
    );

class ReportsViewModel extends Notifier<ReportsState> {
  ReportsProjectPeriod _projectPeriod = ReportsProjectPeriod.lastSevenDays;
  Set<String?> _expandedProjectIds = const {};

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
      projectPeriod: _projectPeriod,
      expandedProjectIds: _expandedProjectIds,
    );
  }

  void setProjectPeriod(ReportsProjectPeriod period) {
    if (_projectPeriod == period) return;
    _projectPeriod = period;
    _expandedProjectIds = const {};
    _updateProjectView();
  }

  void toggleProject(String? projectId) {
    final expanded = {..._expandedProjectIds};
    if (!expanded.remove(projectId)) expanded.add(projectId);
    _expandedProjectIds = Set.unmodifiable(expanded);
    _updateProjectView();
  }

  void _updateProjectView() {
    state = ReportsState(
      summary: state.summary,
      achievements: state.achievements,
      today: state.today,
      projectPeriod: _projectPeriod,
      expandedProjectIds: _expandedProjectIds,
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
