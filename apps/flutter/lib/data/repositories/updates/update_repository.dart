import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';

/// Shared application state for desktop updates. Popup visibility and
/// dismissal are presentation concerns and are not part of this contract.
class UpdateRepositoryState {
  const UpdateRepositoryState({
    required this.enabled,
    required this.isDesktop,
    required this.officialUpdatesAllowed,
    required this.busy,
    required this.channel,
    required this.phase,
    required this.offer,
    required this.error,
    required this.progress,
    required this.lastChecked,
    required this.seenTags,
  });

  final bool enabled;
  final bool isDesktop;
  final bool officialUpdatesAllowed;
  final bool busy;
  final UpdateChannel channel;
  final UpdatePhase phase;
  final UpdateOffer? offer;
  final String? error;
  final double? progress;
  final DateTime? lastChecked;
  final Set<String> seenTags;
}

/// Result of a check request. [newOffer] means an offer should be surfaced to
/// the user; [seenOffer] means an already-acknowledged offer was found.
enum UpdateCheckOutcome { skipped, failed, upToDate, newOffer, seenOffer }

abstract interface class UpdateRepository {
  bool get automaticChecks;
  bool get started;
  UpdateRepositoryState get state;
  Stream<UpdateRepositoryState> watchState();
  Future<void> start();
  Future<void> setChannel(UpdateChannel channel);
  Future<void> update();

  /// Runs an update check. [UpdateCheckOutcome.skipped] means the request was
  /// coalesced or ineligible and shared state was left untouched.
  Future<UpdateCheckOutcome> check({bool manual = false});
  void dispose();
}
