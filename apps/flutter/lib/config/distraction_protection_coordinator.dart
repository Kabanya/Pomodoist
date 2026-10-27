import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/data/repositories/distractions/live_focus_repository.dart';
import 'package:pomodoist/data/services/distractions/focus_bridge.dart';
import 'package:pomodoist/data/services/platform/distraction_native_gateway.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';

class ProtectionCoordinator {
  ProtectionCoordinator({
    required this.focus,
    required this.native,
    required this.flavor,
    required this.preferences,
    this.mascotImage,
    this.bridgePort,
    required this.taskTitle,
  });
  final LiveFocusRepository focus;
  final DistractionNativeGateway native;
  final SharedPreferences? preferences;
  final String flavor;
  final int? bridgePort;
  final Uint8List? mascotImage;
  final Future<String?> Function(String id) taskTitle;
  FocusBridge? bridge;
  DistractionNativeCapabilities? capabilities;
  bool nativeApplied = false, applying = false, disposed = false;
  String? error;
  final List<ResourceAssignment> inventory = [];
  final Map<String, DateTime> _attempts = {};
  final Map<String, Map<String, dynamic>> _commands = {};
  StreamSubscription<void>? _focusSub, _quitSub;
  bool _quitRequested = false, _quitRequestPending = false;
  Completer<void>? _applyingDone;
  StreamSubscription<DistractionNativeApp>? _appSub, _attemptSub;
  Timer? _tick, _status;
  Future<void> start() async {
    capabilities = await native.capabilities();
    final cached = preferences?.getString(
      'focus.bridge.commands.$flavor.${focus.owner}',
    );
    if (cached != null) {
      try {
        _commands.addAll(
          (jsonDecode(cached) as Map).map(
            (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v)),
          ),
        );
      } on Object {
        /* A malformed cache must not prevent protection. */
      }
    }
    final saved = preferences?.getString('discovery.inventory.${focus.owner}');
    if (saved != null) {
      try {
        inventory.addAll(
          (jsonDecode(saved) as List).map(
            (e) => ResourceAssignment.fromJson(Map<String, dynamic>.from(e)),
          ),
        );
      } on Object {
        error = 'The local application list could not be restored.';
      }
    }
    _appSub = native.foregroundApps.listen((app) async {
      if (!focus.discovery || inventory.any((a) => a.id == app.id)) return;
      inventory.add(
        ResourceAssignment.fromJson({
          'id': app.id,
          'kind': 'app',
          'name': app.name,
          'platform': app.platform,
          'category': 'unclassified',
          'source': 'manual',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      await preferences?.setString(
        'discovery.inventory.${focus.owner}',
        jsonEncode(inventory.map((a) => a.json).toList()),
      );
      focus.notify();
    });
    _attemptSub = native.blockedAttempts.listen((app) async {
      if (!focus.collectAttempts) return;
      final now = DateTime.now(), previous = _attempts[app.id];
      if (previous != null &&
          now.difference(previous) < const Duration(seconds: 30)) {
        return;
      }
      _attempts[app.id] = now;
      final key = 'discovery.attempts.${focus.owner}';
      final events = preferences?.getStringList(key) ?? [];
      await preferences?.setStringList(key, [
        ...events.skip(events.length > 99 ? events.length - 99 : 0),
        jsonEncode({
          'id': app.id,
          'kind': 'app',
          'at': now.toUtc().toIso8601String(),
          'sessionId': focus.activeRun?.id,
        }),
      ]);
    });
    bridge = FocusBridge(
      owner: focus.owner,
      listenPort: bridgePort,
      flavor: flavor,
      preferences: preferences,
      state: () async => await _envelope(),
      command: _command,
    );
    await bridge!.start();
    _quitSub = native.quitRequests.listen((_) async {
      _quitRequested = true;
      _quitRequestPending = true;
      try {
        await focus.detachDevice();
      } on Object catch (e) {
        error = e.toString();
        focus.notify();
      } finally {
        _quitRequestPending = false;
      }
    });
    _focusSub = focus.changes.listen((_) => unawaited(apply()));
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(apply()),
    );
    _status = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(report()),
    );
    await apply();
    await report();
  }

  Future<Map<String, dynamic>> _envelope() async {
    final data = focus.envelope;
    final protection = data['protection'];
    if (protection is Map && focus.activeRun?.taskId != null) {
      protection['taskTitle'] = await taskTitle(focus.activeRun!.taskId!);
    }
    return data;
  }

  Future<void> _commandTail = Future.value();
  Future<Map<String, dynamic>> _command(Map<String, dynamic> value) async {
    final previous = _commandTail;
    final done = Completer<void>();
    _commandTail = done.future;
    await previous;
    try {
      return await _executeCommand(value);
    } finally {
      done.complete();
    }
  }

  Future<String> _localPreset(Map<String, dynamic> value) async {
    for (final key in [
      'workSeconds',
      'shortBreakSeconds',
      'longBreakSeconds',
      'intervalsBeforeLongBreak',
    ]) {
      final n = value[key];
      if (n is! int ||
          n < (key == 'intervalsBeforeLongBreak' ? 1 : 60) ||
          n > (key == 'intervalsBeforeLongBreak' ? 12 : 10800)) {
        throw const FormatException('Invalid Focus duration');
      }
    }
    for (final key in [
      'strictMode',
      'allowPause',
      'autoStartBreaks',
      'autoStartWork',
    ]) {
      if (value[key] != null && value[key] is! bool) {
        throw const FormatException('Invalid Focus flag');
      }
    }
    final presets = await focus.local.watchPresets().first;
    final requestedName =
        (value['name'] is String ? value['name'] as String : 'Focus').trim();
    final base = requestedName.isEmpty
        ? 'Focus'
        : requestedName.substring(0, requestedName.length.clamp(0, 120));
    var name = base;
    for (
      var suffix = 2;
      presets.any((p) => p.name.trim().toLowerCase() == name.toLowerCase());
      suffix++
    ) {
      name = '$base ($suffix)';
    }
    final input = CreateFocusPresetInput(
      name: name,
      workSeconds: value['workSeconds'],
      shortBreakSeconds: value['shortBreakSeconds'],
      longBreakSeconds: value['longBreakSeconds'],
      intervalsBeforeLongBreak: value['intervalsBeforeLongBreak'],
      strictMode: value['strictMode'] == true,
      allowPause: value['allowPause'] != false,
      autoStartBreaks: value['autoStartBreaks'] == true,
      autoStartWork: value['autoStartWork'] == true,
    );
    for (final p in presets) {
      if (p.workSeconds == input.workSeconds &&
          p.shortBreakSeconds == input.shortBreakSeconds &&
          p.longBreakSeconds == input.longBreakSeconds &&
          p.intervalsBeforeLongBreak == input.intervalsBeforeLongBreak &&
          p.strictMode == input.strictMode &&
          p.allowPause == input.allowPause &&
          p.autoStartBreaks == input.autoStartBreaks &&
          p.autoStartWork == input.autoStartWork) {
        return p.id;
      }
    }
    return (await focus.local.createPreset(input)).getOrThrow();
  }

  Future<Map<String, dynamic>> _executeCommand(
    Map<String, dynamic> value,
  ) async {
    final requestId = value['requestId'];
    if (requestId is! String || requestId.length > 128) {
      throw const FormatException('Invalid request id');
    }
    // Paired browsers read the same cached authority as GET /state, even offline.
    if (value['action'] == 'read') return _envelope();
    if (!focus.localMode && focus.remote != null) {
      final result = await focus.remote!(value).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          focus.online = false;
          focus.notify();
          throw TimeoutException('Shared Focus is unavailable.');
        },
      );
      await focus.refresh();
      return {
        ...await _envelope(),
        if (result['code'] != null) 'code': result['code'],
      };
    }
    if (_commands.containsKey(requestId)) return _commands[requestId]!;
    if (![
          'read',
          'registerDevice',
          'profileUpsert',
          'assignmentUpsert',
        ].contains(value['action']) &&
        value['expectedRevision'] != focus.localRevision) {
      return {...await _envelope(), 'code': 'revision_conflict'};
    }
    final payload = Map<String, dynamic>.from(value['payload'] as Map? ?? {});
    try {
      switch (value['action']) {
        case 'read':
          break;
        case 'start':
          if (focus.activeRun != null &&
              focus.strict &&
              ['running', 'paused'].contains(focus.activeInterval?.status)) {
            (await focus.stopActiveRun(
              reason: StopFocusReason.interrupted,
            )).getOrThrow();
          }
          final presetId = await _localPreset(
            Map<String, dynamic>.from(payload['preset'] as Map),
          );
          if (payload['strictExitSeconds'] != null &&
              ![0, 60].contains(payload['strictExitSeconds'])) {
            throw const FormatException('Invalid exit policy');
          }
          if (payload['profileId'] != null &&
              !focus.profiles.any((p) => p.id == payload['profileId'])) {
            throw const FormatException('Unknown profile');
          }
          final previousProfile = focus.selectedProfileId;
          final previousExitSeconds = focus.strictExitSeconds;
          focus.selectedProfileId = payload['profileId'];
          focus.strictExitSeconds = payload['strictExitSeconds'] as int? ?? 60;
          try {
            await focus
                .startRun(
                  StartFocusRunInput(
                    presetId: presetId,
                    targetWorkIntervals: payload['targetWorkIntervals'],
                    note: payload['note'],
                    taskId: payload['taskId'],
                    projectId: payload['projectId'],
                  ),
                )
                .then((r) => r.getOrThrow());
          } on Object {
            focus.selectedProfileId = previousProfile;
            focus.strictExitSeconds = previousExitSeconds;
            rethrow;
          }
        case 'changePreset':
          final presetId = await _localPreset(
            Map<String, dynamic>.from(payload['preset'] as Map),
          );
          (await focus.changeActiveRunPreset(presetId)).getOrThrow();
        case 'pause':
          (await focus.pauseActiveInterval()).getOrThrow();
        case 'resume':
          (await focus.resumeActiveInterval()).getOrThrow();
        case 'startReady':
          (await focus.startReadyInterval()).getOrThrow();
        case 'restart':
          (await focus.restartActiveInterval()).getOrThrow();
        case 'skip':
          (await focus.skipActiveInterval()).getOrThrow();
        case 'complete':
          (await focus.completeActiveInterval()).getOrThrow();
        case 'requestStop':
          if (payload['confirmed'] == true && focus.strictExitSeconds == 0) {
            await focus.confirmExit();
          } else {
            (await focus.stopActiveRun(
              reason: StopFocusReason.interrupted,
            )).getOrThrow();
          }
        case 'cancelStop':
          await focus.cancelExit();
        case 'detach':
          await focus.detachDevice(confirmed: payload['confirmed'] == true);
        case 'profileUpsert':
          await focus.saveProfile(
            DistractionProfile.fromJson(
              Map<String, dynamic>.from(payload['profile'] as Map),
            ),
          );
        case 'assignmentUpsert':
          await focus.saveAssignment(
            ResourceAssignment.fromJson(
              Map<String, dynamic>.from(payload['assignment'] as Map),
            ),
          );
        case 'registerDevice':
          focus.devices = [
            ...focus.devices.where((d) => d['deviceId'] != value['deviceId']),
            {
              'deviceId': value['deviceId'],
              'platform': 'chrome',
              'name': 'Chrome',
              'capabilities': payload['capabilities'] is Map
                  ? payload['capabilities']
                  : {},
              'appliedRevision': payload['appliedRevision'],
              'detached': false,
              'lastSeenAt': focus.now().toUtc().toIso8601String(),
            },
          ];
          focus.notify();
          break;
        default:
          throw const FormatException('Unsupported Focus command');
      }
    } on Object {
      if (focus.pendingExitAction != null) {
        return await _remember(requestId, {
          ...await _envelope(),
          'code': focus.effectiveStrictExitSeconds == 60
              ? 'strict_exit_pending'
              : 'strict_confirmation_required',
        });
      }
      rethrow;
    }
    return _remember(requestId, await _envelope());
  }

  Future<Map<String, dynamic>> _remember(
    String requestId,
    Map<String, dynamic> result,
  ) async {
    if (_commands.length >= 64) _commands.remove(_commands.keys.first);
    _commands[requestId] = result;
    await preferences?.setString(
      'focus.bridge.commands.$flavor.${focus.owner}',
      jsonEncode(_commands),
    );
    return result;
  }

  Future<void> apply() async {
    if (disposed || applying) return;
    applying = true;
    _applyingDone = Completer<void>();
    try {
      if (_quitRequested && focus.detached) {
        await bridge?.revoke();
        await native.clearProtection();
        await native.allowQuit();
        return;
      }
      if (_quitRequested &&
          !_quitRequestPending &&
          focus.pendingExitAction == null &&
          focus.exitAt == null &&
          !focus.detached) {
        _quitRequested = false;
      }
      if (focus.discovery && capabilities?.discoveryAvailable == true) {
        await native.startDiscovery();
      } else {
        await native.stopDiscovery();
      }
      final snapshot = focus.protection;
      if (snapshot == null) {
        final interval = focus.activeInterval;
        final guardExpiry = focus.guardExpiry;
        if (!focus.detached &&
            focus.activeRun != null &&
            guardExpiry != null &&
            guardExpiry.isAfter(focus.now())) {
          await native.setProtection(
            active: true,
            blockedApps: [],
            taskTitle: '',
            remainingSeconds: interval?.plannedSeconds ?? 0,
            expiresAt: guardExpiry,
            countdown: interval?.status == 'running',
          );
        } else {
          await native.clearProtection();
        }
        nativeApplied = false;
      } else {
        final profile = focus.selectedProfile!;
        final known = {
          for (final a in [...inventory, ...focus.assignments])
            '${a.kind}:${a.id}': a,
        };
        final blocked = <String>{
          for (final a in known.values)
            if (a.kind == 'app' && profile.blocks(a.kind, a.id, a.category))
              a.id,
          for (final r in profile.overrides)
            if (r['kind'] == 'app' && r['action'] == 'block') r['id'] as String,
        };
        await native.setProtection(
          active: true,
          blockedApps: blocked.toList(),
          taskTitle: focus.activeRun?.taskId == null
              ? ''
              : await taskTitle(focus.activeRun!.taskId!) ?? '',
          remainingSeconds: snapshot['remainingSeconds'] as int,
          countdown: snapshot['status'] == 'running',
          expiresAt: DateTime.parse(snapshot['expiresAt'] as String),
          mascotImage: mascotImage,
        );
        nativeApplied = capabilities?.supported == true;
      }
      error = null;
    } on Object catch (e) {
      error = e.toString();
      nativeApplied = false;
    } finally {
      applying = false;
      _applyingDone?.complete();
    }
  }

  Future<void> report() async {
    if (!focus.online || focus.remote == null || disposed) return;
    try {
      await focus.command('registerDevice', {
        'platform': capabilities?.platform ?? 'unknown',
        'capabilities': {
          'native': capabilities?.supported == true,
          'nativeApplied': nativeApplied,
          'discovery': capabilities?.discoveryAvailable == true,
          'adapter': capabilities?.adapter,
          'reason': capabilities?.reason,
        },
        'appliedRevision': nativeApplied && focus.session != null
            ? focus.session!['revision']
            : null,
      });
    } on Object catch (e) {
      error = e.toString();
    }
  }

  Future<void> dispose() async {
    disposed = true;
    _tick?.cancel();
    _status?.cancel();
    await _focusSub?.cancel();
    await _quitSub?.cancel();
    await _appSub?.cancel();
    await _attemptSub?.cancel();
    await bridge?.dispose();
    await _applyingDone?.future;
    await native.clearProtection();
    await native.stopDiscovery();
    await native.dispose();
  }
}
