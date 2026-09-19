import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';

final class SharedProjectBadgeState {
  const SharedProjectBadgeState({required this.hasConflicts});
  final bool hasConflicts;
}

final sharedProjectBadgeViewModelProvider = NotifierProvider.autoDispose
    .family<SharedProjectBadgeViewModel, SharedProjectBadgeState, String>(
      SharedProjectBadgeViewModel.new,
    );

class SharedProjectBadgeViewModel extends Notifier<SharedProjectBadgeState> {
  SharedProjectBadgeViewModel(this.scopeId);
  final String scopeId;
  @override
  SharedProjectBadgeState build() => SharedProjectBadgeState(
    hasConflicts:
        ref.watch(scopeConflictsProvider(scopeId)).value?.isNotEmpty ?? false,
  );
}
