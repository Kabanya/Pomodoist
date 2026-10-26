import 'dart:async';
import 'package:pomodoist/data/repositories/distractions/distraction_repository.dart';
import 'package:pomodoist/data/repositories/distractions/live_focus_repository.dart';
import 'package:pomodoist/config/distraction_protection_coordinator.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';

class CoordinatedDistractionRepository implements DistractionRepository {
  CoordinatedDistractionRepository(
    this.focus, {
    required this.protection,
    required this.classifyResource,
  });
  final LiveFocusRepository focus;
  final ProtectionCoordinator? Function() protection;
  final Future<ResourceAssignment> Function(ResourceAssignment)
  classifyResource;
  bool automatic = false;
  @override
  Stream<void> get changes => focus.changes;
  @override
  DistractionSettingsState get state {
    final p = protection();
    return DistractionSettingsState(
      available: true,
      profiles: focus.profiles,
      assignments: focus.assignments,
      inventory: p?.inventory ?? [],
      devices: focus.deviceStatuses,
      profileId: focus.selectedProfileId,
      local: focus.localMode,
      online: focus.online,
      conflict: focus.conflict,
      active: focus.activeRun != null,
      strict: focus.strict,
      strictExitSeconds: focus.effectiveStrictExitSeconds,
      exitRemaining: focus.exitRemaining,
      exitPending: focus.pendingExitAction != null || focus.exitAt != null,
      discovery: focus.discovery,
      collectAttempts: focus.collectAttempts,
      automatic: automatic,
      nativeSupported: p?.capabilities?.supported == true,
      nativeApplied: p?.nativeApplied == true,
      nativeReason: p?.capabilities?.reason,
      error: focus.error ?? p?.error ?? p?.bridge?.error,
      pairingCode: p?.bridge?.pairingCode,
      bridgePort: p?.bridge?.port ?? 0,
      sessionRevision: focus.localMode
          ? focus.localRevision
          : focus.session?['revision'] as int?,
    );
  }

  @override
  Future<void> configure({
    String? profileId,
    int? strictExitSeconds,
    bool? discovery,
    bool? collectAttempts,
    bool? automatic,
    bool clearProfile = false,
  }) async {
    if (focus.activeRun != null &&
        (profileId != null || clearProfile || strictExitSeconds != null)) {
      throw StateError(
        'Choose the profile and exit policy before starting Focus.',
      );
    }
    if (clearProfile) {
      focus.selectedProfileId = null;
    } else if (profileId != null) {
      focus.selectedProfileId = profileId;
    }
    if (strictExitSeconds != null) {
      focus.strictExitSeconds = strictExitSeconds == 0 ? 0 : 60;
    }
    if (discovery != null) focus.discovery = discovery;
    if (collectAttempts != null) focus.collectAttempts = collectAttempts;
    if (automatic != null) {
      this.automatic = automatic;
      await focus.preferences?.setBool(
        'distractions.automatic.${focus.owner}',
        automatic,
      );
    }
    await focus.persist();
    await protection()?.apply();
  }

  @override
  Future<void> saveProfile(DistractionProfile p) => focus.saveProfile(p);
  @override
  Future<void> saveAssignment(ResourceAssignment a) => focus.saveAssignment(a);
  @override
  Future<void> classify(ResourceAssignment r) async {
    final value = await classifyResource(r);
    await focus.saveAssignment(value);
  }

  @override
  Future<void> pair() async {
    protection()?.bridge?.pair();
    focus.notify();
  }

  @override
  Future<void> cancelExit() => focus.cancelExit();
  @override
  Future<void> confirmExit() =>
      focus.confirmExit(detach: focus.pendingExitAction == 'detach');
  @override
  Future<void> requestExit() async {
    (await focus.stopActiveRun(
      reason: StopFocusReason.interrupted,
    )).getOrThrow();
  }

  @override
  Future<void> joinShared() => focus.joinShared();
  @override
  Future<void> finishLocal() async {
    if (!focus.localMode) return;
    (await focus.stopActiveRun(
      reason: StopFocusReason.interrupted,
    )).getOrThrow();
    focus.localMode = false;
    focus.conflict = false;
    await focus.persist();
  }

  @override
  Future<bool> detach() async {
    final result = await focus.detachDevice();
    if (result) await protection()?.bridge?.revoke();
    return result;
  }
}
