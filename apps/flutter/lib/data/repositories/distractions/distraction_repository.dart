import 'package:pomodoist/domain/models/distractions/distraction_models.dart';

class DistractionSettingsState {
  const DistractionSettingsState({
    this.available = false,
    this.profiles = const [],
    this.assignments = const [],
    this.inventory = const [],
    this.devices = const [],
    this.profileId,
    this.local = false,
    this.online = false,
    this.conflict = false,
    this.active = false,
    this.strict = false,
    this.strictExitSeconds = 60,
    this.exitRemaining = 0,
    this.exitPending = false,
    this.discovery = false,
    this.collectAttempts = false,
    this.automatic = false,
    this.nativeSupported = false,
    this.nativeApplied = false,
    this.nativeReason,
    this.error,
    this.pairingCode,
    this.bridgePort = 0,
    this.sessionRevision,
  });
  final bool available,
      local,
      online,
      conflict,
      active,
      strict,
      exitPending,
      discovery,
      collectAttempts,
      automatic,
      nativeSupported,
      nativeApplied;
  final int strictExitSeconds, exitRemaining, bridgePort;
  final int? sessionRevision;
  final String? profileId, nativeReason, error, pairingCode;
  final List<DistractionProfile> profiles;
  final List<ResourceAssignment> assignments, inventory;
  final List<Map<String, dynamic>> devices;
}

abstract interface class DistractionRepository {
  DistractionSettingsState get state;
  Stream<void> get changes;
  Future<void> configure({
    String? profileId,
    int? strictExitSeconds,
    bool? discovery,
    bool? collectAttempts,
    bool? automatic,
    bool clearProfile = false,
  });
  Future<void> saveProfile(DistractionProfile profile);
  Future<void> saveAssignment(ResourceAssignment assignment);
  Future<void> classify(ResourceAssignment resource);
  Future<void> pair();
  Future<void> cancelExit();
  Future<void> confirmExit();
  Future<void> requestExit();
  Future<void> joinShared();
  Future<void> finishLocal();
  Future<bool> detach();
}
