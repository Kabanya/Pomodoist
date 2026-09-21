import 'dart:async';

import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';

import 'strict_fake.dart';

/// In-memory [UpdateSource] double.
///
/// [findUpdate] answers with [offer] unless [findUpdateError] is set, and
/// records every call in [findUpdateCalls].
class FakeUpdateSource extends StrictFake implements UpdateSource {
  /// Offer [findUpdate] succeeds with. Null means no update is available.
  UpdateOffer? offer;

  /// When non-null, [findUpdate] throws it instead of returning [offer].
  Object? findUpdateError;

  /// When set, [findUpdate] stays pending until the completer resolves.
  Completer<void>? findUpdateGate;

  /// Arguments of each [findUpdate] call.
  final findUpdateCalls =
      <({UpdateVersion current, UpdateTarget target, UpdateChannel channel})>[];

  final disposeCalls = <void>[];

  @override
  Future<UpdateOffer?> findUpdate({
    required UpdateVersion current,
    required UpdateTarget target,
    required UpdateChannel channel,
  }) async {
    findUpdateCalls.add((current: current, target: target, channel: channel));
    await findUpdateGate?.future;
    final error = findUpdateError;
    if (error != null) throw error;
    return offer;
  }

  @override
  void dispose() {
    disposeCalls.add(null);
  }
}

/// In-memory [UpdateInstaller] double.
///
/// [install] records its offer and progress callback without driving any phase
/// itself — a test replays the phases through the recorded callback — and
/// [acknowledgeStartup] answers with [acknowledgedStartup].
class FakeUpdateInstaller extends StrictFake implements UpdateInstaller {
  @override
  UpdateTarget? target = const UpdateTarget(UpdateOS.linux, UpdateArch.x64);

  @override
  String? unavailableReason;

  /// Value [acknowledgeStartup] succeeds with.
  String? acknowledgedStartup;

  /// When non-null, the matching method throws it.
  Object? acknowledgeStartupError;
  Object? installError;

  /// When set, [install] stays pending until the completer resolves.
  Completer<void>? installGate;

  /// Arguments of each [install] call.
  final installCalls = <({UpdateOffer offer, UpdateProgress progress})>[];

  final acknowledgeStartupCalls = <void>[];
  final disposeCalls = <void>[];

  @override
  Future<String?> acknowledgeStartup() async {
    acknowledgeStartupCalls.add(null);
    final error = acknowledgeStartupError;
    if (error != null) throw error;
    return acknowledgedStartup;
  }

  @override
  Future<void> install(UpdateOffer offer, UpdateProgress progress) async {
    installCalls.add((offer: offer, progress: progress));
    await installGate?.future;
    final error = installError;
    if (error != null) throw error;
  }

  @override
  void dispose() {
    disposeCalls.add(null);
  }
}
