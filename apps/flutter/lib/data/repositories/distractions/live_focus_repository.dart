import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/data/services/distractions/focus_wire.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/utils/timer_engine.dart';

typedef FocusRemote =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> command);

/// A single command boundary for every existing Focus entry point.
class LiveFocusRepository implements FocusRepository {
  LiveFocusRepository({
    required this.local,
    required this.remote,
    required this.owner,
    required this.deviceId,
    required this.preferences,
    this.onAdopted,
    this.onServerOwned,
    this.adoptionHistory,
    this.onTransition,
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;
  final FocusRepository local;
  final FocusRemote? remote;
  final String owner, deviceId;
  final SharedPreferences? preferences;
  final Future<void> Function(String runId)? onAdopted;
  final void Function(String runId)? onServerOwned;
  final Future<Map<String, dynamic>> Function(
    String runId,
    String currentIntervalId,
  )?
  adoptionHistory;
  final Future<void> Function(
    Map<String, dynamic>? previous,
    Map<String, dynamic>? next,
  )?
  onTransition;
  final DateTime Function() now;
  final _changes = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changes.stream;
  StreamSubscription<FocusRunItem?>? _runSub;
  StreamSubscription<FocusIntervalItem?>? _intervalSub;
  Timer? _poll, _exitTimer;
  FocusRunItem? _localRun;
  FocusIntervalItem? _localInterval;
  Map<String, dynamic>? session;
  List<DistractionProfile> profiles = [];
  List<ResourceAssignment> assignments = [];
  List<Map<String, dynamic>> devices = [];
  bool online = false,
      localMode = false,
      conflict = false,
      disposed = false,
      detached = false;
  bool discovery = false, collectAttempts = false;
  String? localProfileId;
  String? selectedProfileId, error, pendingExitAction, pendingAdoptionRunId;
  DateTime? localExitAt;
  int strictExitSeconds = 60;
  final List<Map<String, dynamic>> pendingSettings = [];
  final Set<String> adoptedRunIds = {};
  final Set<String> serverOwnedRunIds = {};
  void _rememberServerRun(String id) {
    serverOwnedRunIds.add(id);
    onServerOwned?.call(id);
  }

  bool _refreshing = false;
  int _settingsRevision = 0;
  DateTime? _lastConfirmedAt;
  Future<void> _tail = Future.value();
  String get _key => 'distractions.v1.$owner';
  List<Map<String, dynamic>> get deviceStatuses =>
      localMode ? devices : devices.map(_localDates).toList();
  bool get sharedActive =>
      session?['run'] is Map &&
      ['active', 'paused'].contains(session!['run']['status']);
  FocusRunItem? get activeRun => localMode
      ? _localRun
      : sharedActive
      ? liveRun(_localDates(session!['run']))
      : null;
  FocusIntervalItem? get activeInterval => localMode
      ? _localInterval
      : sharedActive && session?['interval'] is Map
      ? liveInterval(_localDates(session!['interval']))
      : null;
  DistractionProfile? get selectedProfile {
    final id = localMode
        ? localProfileId
        : (sharedActive ? session!['profileId'] as String? : selectedProfileId);
    for (final p in profiles) {
      if (p.id == id && !p.isDeleted) return p;
    }
    return null;
  }

  bool get strict =>
      localMode ? _localStrict : session?['preset']?['strictMode'] == true;
  bool _localStrict = false;
  Map<String, dynamic>? localPreset;
  int _serverOffsetMilliseconds = 0;
  int localRevision = 0;
  int get effectiveStrictExitSeconds => localMode
      ? strictExitSeconds
      : session?['strictExitSeconds'] as int? ?? strictExitSeconds;
  DateTime _localTime(DateTime date) =>
      date.subtract(Duration(milliseconds: _serverOffsetMilliseconds));
  Map<String, dynamic> _localDates(Map source) => {
    for (final e in source.entries)
      e.key as String:
          const [
                'startedAt',
                'pausedAt',
                'completedAt',
                'stoppedAt',
                'createdAt',
                'updatedAt',
                'endedAt',
                'exitRequestedAt',
                'lastSeenAt',
                'protectionExpiresAt',
              ].contains(e.key) &&
              e.value is String
          ? _localTime(DateTime.parse(e.value)).toIso8601String()
          : e.value,
  };
  DateTime? get exitAt {
    if (localExitAt != null) return localExitAt;
    final own = devices.where((d) => d['deviceId'] == deviceId).firstOrNull;
    final requested = DateTime.tryParse(
      '${own?['exitRequestedAt'] ?? session?['exitRequestedAt']}',
    );
    return requested == null
        ? null
        : _localTime(
            requested,
          ).add(Duration(seconds: effectiveStrictExitSeconds));
  }

  int get exitRemaining =>
      exitAt == null ? 0 : exitAt!.difference(now()).inSeconds.clamp(0, 60);
  void notify() {
    if (!disposed) _changes.add(null);
  }

  Future<void> start() async {
    try {
      final raw = preferences?.getString(_key);
      if (raw != null) {
        final data = jsonDecode(raw) as Map;
        profiles = (data['profiles'] as List)
            .map(
              (p) => DistractionProfile.fromJson(Map<String, dynamic>.from(p)),
            )
            .toList();
        assignments = (data['assignments'] as List)
            .map(
              (p) => ResourceAssignment.fromJson(Map<String, dynamic>.from(p)),
            )
            .toList();
        selectedProfileId = data['selectedProfileId'];
        localProfileId = data.containsKey('localProfileId')
            ? data['localProfileId']
            : selectedProfileId;
        strictExitSeconds = data['strictExitSeconds'] == 0 ? 0 : 60;
        discovery = data['discovery'] == true;
        collectAttempts = data['collectAttempts'] == true;
        localMode = data['localMode'] == true;
        pendingAdoptionRunId = data['pendingAdoptionRunId'];
        detached = data['detached'] == true;
        localExitAt = DateTime.tryParse('${data['localExitAt']}');
        pendingExitAction = data['pendingExitAction'];
        _localStrict = data['localStrict'] == true;
        localRevision = data['localRevision'] as int? ?? 0;
        _settingsRevision = data['settingsRevision'] as int? ?? 0;
        localPreset = data['localPreset'] is Map
            ? Map<String, dynamic>.from(data['localPreset'])
            : null;
        _serverOffsetMilliseconds =
            data['serverOffsetMilliseconds'] as int? ?? 0;
        pendingSettings.addAll(
          (data['pendingSettings'] as List? ?? []).map(
            (e) => Map<String, dynamic>.from(e),
          ),
        );
        serverOwnedRunIds.addAll(
          List<String>.from(data['serverOwnedRunIds'] as List? ?? []),
        );
        adoptedRunIds.addAll(
          List<String>.from(data['adoptedRunIds'] as List? ?? []),
        );
        if (data['session'] is Map) {
          session = Map<String, dynamic>.from(data['session']);
        }
      }
    } on Object {
      error = 'Saved protection state could not be restored.';
    }
    if (profiles.isEmpty) {
      profiles = [
        for (final name in ['Work', 'Study'])
          DistractionProfile.fromJson({
            'id': name.toLowerCase(),
            'name': name,
            'blockedCategories': <String>[],
            'overrides': <dynamic>[],
            'blockOnPause': true,
            'blockOnShortBreak': false,
            'blockOnLongBreak': false,
            'updatedAt': now().toUtc().toIso8601String(),
          }),
      ];
    }
    await _acknowledgePendingAdoption();
    for (final id in serverOwnedRunIds) {
      onServerOwned?.call(id);
    }
    if (session?['id'] is String) _rememberServerRun(session!['id']);
    for (final id in adoptedRunIds) {
      _rememberServerRun(id);
      await onAdopted?.call(id);
    }
    _runSub = local.watchActiveRun().listen((v) async {
      _localRun = v;
      if (v != null && !sharedActive && !adoptedRunIds.contains(v.id)) {
        localMode = true;
        if (localPreset == null) {
          final values = await local.watchPresets().first;
          final p = selectedFocusPresetOrDefault(values, v.presetId);
          if (p != null) {
            localPreset = presetWire(p);
            _localStrict = p.strictMode;
            await persist();
          }
        }
      }
      notify();
    });
    _intervalSub = local.watchActiveInterval().listen((v) {
      _localInterval = v;
      notify();
    });
    _poll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(refresh()),
    );
    _exitTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (localExitAt != null && !now().isBefore(localExitAt!)) {
        final action = pendingExitAction;
        if (action == 'detach') detached = true;
        if (!localMode) {
          localExitAt = null;
          pendingExitAction = null;
          localRevision++;
          await persist();
          return;
        }
        localExitAt = null;
        pendingExitAction = null;
        await local.stopActiveRun(reason: StopFocusReason.interrupted);
        await _readLocal();
        localRevision++;
        await persist();
      }
      if (exitAt != null) {
        if (!localMode && exitRemaining == 0) unawaited(refresh());
        notify();
      }
    });
    await _readLocal();
    await refresh();
    notify();
  }

  Future<void> _readLocal() async {
    _localRun = await local.watchActiveRun().first;
    _localInterval = await local.watchActiveInterval().first;
  }

  Future<void> persist() async {
    final saved = await preferences?.setString(
      _key,
      jsonEncode({
        'pendingSettings': pendingSettings,
        'adoptedRunIds': adoptedRunIds.toList(),
        'serverOwnedRunIds': serverOwnedRunIds.toList(),
        'profiles': profiles.map((p) => p.json).toList(),
        'assignments': assignments.map((p) => p.json).toList(),
        'selectedProfileId': selectedProfileId,
        'localProfileId': localProfileId,
        'strictExitSeconds': strictExitSeconds,
        'discovery': discovery,
        'collectAttempts': collectAttempts,
        'localMode': localMode,
        'pendingAdoptionRunId': pendingAdoptionRunId,
        'localStrict': _localStrict,
        'localRevision': localRevision,
        'settingsRevision': _settingsRevision,
        'localPreset': localPreset,
        'serverOffsetMilliseconds': _serverOffsetMilliseconds,
        'detached': detached,
        'session': session,
        'localExitAt': localExitAt?.toUtc().toIso8601String(),
        'pendingExitAction': pendingExitAction,
      }),
    );
    if (saved == false) {
      throw StateError('Protection settings could not be saved.');
    }
    notify();
  }

  void _apply(Map<String, dynamic> value, DateTime observedAt) {
    final serverNow = DateTime.tryParse('${value['serverNow']}');
    if (serverNow != null) {
      _serverOffsetMilliseconds = serverNow
          .difference(observedAt)
          .inMilliseconds;
    }
    _lastConfirmedAt = now();
    _settingsRevision = value['settingsRevision'] as int? ?? _settingsRevision;
    session = value['session'] == null
        ? null
        : Map<String, dynamic>.from(value['session']);
    if (session?['id'] is String) _rememberServerRun(session!['id']);
    if (value['profiles'] is List) {
      profiles = (value['profiles'] as List)
          .map((p) => DistractionProfile.fromJson(Map<String, dynamic>.from(p)))
          .where((p) => !p.isDeleted)
          .toList();
    }
    if (value['assignments'] is List) {
      assignments = (value['assignments'] as List)
          .map((p) => ResourceAssignment.fromJson(Map<String, dynamic>.from(p)))
          .where((p) => !p.isDeleted)
          .toList();
    }
    if (value['devices'] is List) {
      devices = (value['devices'] as List)
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
    }
    for (final pending in pendingSettings) {
      if (pending['action'] == 'profileUpsert') {
        final p = DistractionProfile.fromJson(
          Map<String, dynamic>.from(pending['payload']['profile']),
        );
        profiles = [
          ...profiles.where((v) => v.id != p.id),
          if (!p.isDeleted) p,
        ];
      }
      if (pending['action'] == 'assignmentUpsert') {
        final a = ResourceAssignment.fromJson(
          Map<String, dynamic>.from(pending['payload']['assignment']),
        );
        assignments = [
          ...assignments.where((v) => v.kind != a.kind || v.id != a.id),
          if (!a.isDeleted) a,
        ];
      }
    }
    final device = devices.where((d) => d['deviceId'] == deviceId).firstOrNull;
    if (device != null) detached = device['detached'] == true;
    online = true;
    error = null;
  }

  Future<Map<String, dynamic>> command(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (remote == null) throw StateError('Shared Focus requires an account.');
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      final observedAt = now();
      final result = await remote!({
        'action': action,
        'requestId': const Uuid().v4(),
        'deviceId': deviceId,
        'expectedRevision': session?['revision'] ?? 0,
        if (action == 'profileUpsert' || action == 'assignmentUpsert')
          'expectedSettingsRevision': _settingsRevision,
        'payload': payload,
      }).timeout(const Duration(seconds: 12));
      final previousSession = session;
      _apply(result, observedAt);
      if (!sharedActive || detached) {
        pendingExitAction = null;
      }
      await persist();
      if (!localMode || payload.containsKey('adopt')) {
        try {
          await onTransition?.call(
            previousSession,
            session == null
                ? null
                : {
                    ...session!,
                    'effectAction': payload.containsKey('adopt')
                        ? 'adopt'
                        : action,
                    'effectObservedAt': observedAt.toUtc().toIso8601String(),
                  },
          );
        } on Object {
          /* Accepted Focus state survives presentation failures. */
        }
      }
      if (result['code'] == 'strict_exit_pending' ||
          result['code'] == 'strict_confirmation_required') {
        pendingExitAction = action;
        notify();
        throw StateError(
          'Focus exit requires confirmation or the exit countdown.',
        );
      }
      if (result['code'] != null &&
          !['ok', 'manual_assignment_preserved'].contains(result['code'])) {
        throw StateError('${result['code']}');
      }
      return result;
    } on TimeoutException {
      online = false;
      notify();
      rethrow;
    } finally {
      done.complete();
    }
  }

  Future<void> _acknowledgePendingAdoption() async {
    final id = pendingAdoptionRunId;
    if (id == null || session?['id'] != id) return;
    adoptedRunIds.add(id);
    await persist();
    await onAdopted?.call(id);
    pendingAdoptionRunId = null;
    localMode = false;
    conflict = false;
    await persist();
  }

  Future<void> refresh() async {
    if (_refreshing || remote == null || disposed) return;
    _refreshing = true;
    try {
      for (final pending in List<Map<String, dynamic>>.from(pendingSettings)) {
        await command(
          pending['action'] as String,
          Map<String, dynamic>.from(pending['payload']),
        );
        pendingSettings.remove(pending);
        await persist();
      }
      final previousSession = session, previousConfirmation = _lastConfirmedAt;
      await command('read');
      await _acknowledgePendingAdoption();
      await _autoStartReady(previousSession, previousConfirmation);
      if (localMode && _localRun != null && _localInterval != null) {
        if (sharedActive && session!['id'] != _localRun!.id) {
          conflict = true;
          notify();
        } else if (!sharedActive) {
          final presets = await local.watchPresets().first;
          final p = selectedFocusPresetOrDefault(presets, _localRun!.presetId);
          final snapshot = localPreset ?? (p == null ? null : presetWire(p));
          if (snapshot != null) {
            final run = _localRun!, interval = _localInterval!;
            pendingAdoptionRunId = run.id;
            await persist();
            await command('start', {
              'preset': snapshot,
              'profileId': localProfileId,
              'strictExitSeconds': strictExitSeconds,
              'adopt': {
                ...?await adoptionHistory?.call(run.id, interval.id),
                'run': runWire(run),
                'interval': intervalWire(interval),
              },
            });
            await _acknowledgePendingAdoption();
          }
        } else {
          final id = _localRun!.id;
          adoptedRunIds.add(id);
          await persist();
          await onAdopted?.call(id);
          localMode = false;
          conflict = false;
          await persist();
        }
      }
    } on Object catch (e) {
      if (e is! StateError) online = false;
      if (localMode && sharedActive && session!['id'] != _localRun?.id) {
        conflict = true;
      }
      error = e.toString();
      notify();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _autoStartReady(
    Map<String, dynamic>? previous,
    DateTime? previousConfirmation,
  ) async {
    if (previousConfirmation == null ||
        now().difference(previousConfirmation) > const Duration(seconds: 30) ||
        localMode ||
        !online ||
        !sharedActive ||
        exitAt != null ||
        activeInterval?.status != 'ready' ||
        previous?['interval']?['status'] != 'running' ||
        previous?['interval']?['id'] == session?['interval']?['id']) {
      return;
    }
    final deadline = DateTime.tryParse('${previous?['protectionExpiresAt']}');
    if (deadline == null ||
        now().isBefore(_localTime(deadline)) ||
        now().difference(_localTime(deadline)).inSeconds > 30) {
      return;
    }
    final phase = activeInterval!.type;
    if (session?['preset']?[phase == 'work'
            ? 'autoStartWork'
            : 'autoStartBreaks'] ==
        true) {
      await command('startReady');
    }
  }

  Future<void> joinShared() async {
    if (!conflict) return;
    if (strict && _localRun != null) {
      await _guardLocal('join');
      return;
    }
    (await local.stopActiveRun(
      reason: StopFocusReason.interrupted,
    )).getOrThrow();
    localMode = false;
    conflict = false;
    await persist();
  }

  Future<void> chooseLocal() async {
    conflict = false;
    localMode = true;
    await persist();
  }

  Future<void> _saveSettings(void Function() change) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    final oldProfiles = profiles, oldAssignments = assignments;
    final oldPending = List<Map<String, dynamic>>.from(pendingSettings);
    try {
      change();
      await persist();
    } on Object {
      profiles = oldProfiles;
      assignments = oldAssignments;
      pendingSettings
        ..clear()
        ..addAll(oldPending);
      rethrow;
    } finally {
      done.complete();
    }
  }

  Future<void> saveProfile(DistractionProfile profile) async {
    if (online && remote != null) {
      await command('profileUpsert', {'profile': profile.json});
    } else {
      await _saveSettings(() {
        pendingSettings.removeWhere(
          (p) =>
              p['action'] == 'profileUpsert' &&
              p['payload']['profile']['id'] == profile.id,
        );
        pendingSettings.add({
          'action': 'profileUpsert',
          'payload': {'profile': profile.json},
        });
        profiles = [
          ...profiles.where((p) => p.id != profile.id),
          if (!profile.isDeleted) profile,
        ];
      });
    }
  }

  Future<void> saveAssignment(ResourceAssignment value) async {
    if (online && remote != null) {
      await command('assignmentUpsert', {'assignment': value.json});
    } else {
      await _saveSettings(() {
        final old = assignments
            .where((a) => a.kind == value.kind && a.id == value.id)
            .firstOrNull;
        final merged = mergeAssignment(old, value);
        pendingSettings.removeWhere(
          (p) =>
              p['action'] == 'assignmentUpsert' &&
              p['payload']['assignment']['id'] == value.id &&
              p['payload']['assignment']['kind'] == value.kind,
        );
        pendingSettings.add({
          'action': 'assignmentUpsert',
          'payload': {'assignment': merged.json},
        });
        assignments = [
          ...assignments.where((a) => a.kind != value.kind || a.id != value.id),
          merged,
        ];
      });
    }
  }

  DateTime? get guardExpiry {
    if (detached || activeRun == null) return null;
    if (localMode) return now().add(const Duration(minutes: 5));
    final expiry = DateTime.tryParse('${session?['protectionExpiresAt']}');
    final confirmed = DateTime.tryParse('${session?['serverNow']}');
    return expiry != null
        ? _localTime(expiry)
        : confirmed == null
        ? null
        : _localTime(confirmed).add(const Duration(minutes: 5));
  }

  Map<String, dynamic>? get protection {
    final run = activeRun, interval = activeInterval, profile = selectedProfile;
    if (detached ||
        run == null ||
        interval == null ||
        profile == null ||
        !profile.applies(interval.type, interval.status, strict)) {
      return null;
    }
    final remaining = calculateRemaining(
      now: now(),
      startedAt: interval.startedAt,
      plannedSeconds: interval.plannedSeconds,
      pausedTotalSeconds: interval.pausedTotalSeconds,
      pausedAt: interval.pausedAt,
    ).inSeconds;
    final expiry = localMode
        ? (interval.status == 'paused'
              ? now().add(const Duration(minutes: 5))
              : calculateExpectedEndAt(
                  startedAt: interval.startedAt,
                  plannedSeconds: interval.plannedSeconds,
                  pausedTotalSeconds: interval.pausedTotalSeconds,
                ))
        : DateTime.tryParse('${session?['protectionExpiresAt']}') == null
        ? null
        : _localTime(DateTime.parse(session!['protectionExpiresAt']));
    if (expiry == null || !expiry.isAfter(now()) || remaining <= 0) return null;
    return {
      'version': 1,
      'owner': owner,
      'sessionId': run.id,
      'revision': session?['revision'] ?? 0,
      'phase': interval.type,
      'status': interval.status,
      'strict': strict,
      'expiresAt': expiry.toUtc().toIso8601String(),
      'remainingSeconds': remaining,
      'taskId': run.taskId,
      'profile': profile.json,
      'assignments': assignments.map((a) => a.json).toList(),
    };
  }

  Map<String, dynamic> get envelope => {
    'session': localMode && _localRun != null && _localInterval != null
        ? {
            'id': _localRun!.id,
            'revision': localRevision,
            'exitRequestedAt': localExitAt
                ?.subtract(const Duration(seconds: 60))
                .toUtc()
                .toIso8601String(),
            'run': runWire(_localRun!),
            'interval': intervalWire(_localInterval!),
            'preset': localPreset ?? {'strictMode': strict},
            'profileId': localProfileId,
            'strictExitSeconds': strictExitSeconds,
            'protectionExpiresAt': protection?['expiresAt'],
          }
        : session == null
        ? null
        : {
            ...session!,
            'run': _localDates(session!['run']),
            'interval': _localDates(session!['interval']),
            'serverNow': now().toUtc().toIso8601String(),
            'protectionExpiresAt': guardExpiry?.toUtc().toIso8601String(),
            if (session!['exitRequestedAt'] != null)
              'exitRequestedAt': _localTime(
                DateTime.parse(session!['exitRequestedAt']),
              ).toUtc().toIso8601String(),
          },
    'serverNow': now().toUtc().toIso8601String(),
    'settingsRevision': localMode ? localRevision : _settingsRevision,
    'profiles': profiles.map((p) => p.json).toList(),
    'assignments': assignments.map((p) => p.json).toList(),
    'devices': localMode ? devices : devices.map(_localDates).toList(),
    'protection': protection,
    'local': localMode,
  };
  Future<void> _guardLocal(String action, {bool confirmed = false}) async {
    if (!strict ||
        activeRun == null ||
        !['running', 'paused'].contains(activeInterval?.status)) {
      return;
    }
    if (effectiveStrictExitSeconds == 0 && confirmed) return;
    final changed =
        pendingExitAction != action ||
        (effectiveStrictExitSeconds == 60 && localExitAt == null);
    pendingExitAction = action;
    if (changed) localRevision++;
    if (effectiveStrictExitSeconds == 60) {
      localExitAt ??= now().add(const Duration(seconds: 60));
    }
    await persist();
    throw StateError('Focus exit requires confirmation or the exit countdown.');
  }

  Future<void> cancelExit() async {
    if (!localMode && online && remote != null) await command('cancelStop');
    localExitAt = null;
    pendingExitAction = null;
    localRevision++;
    await persist();
  }

  Future<void> confirmExit({bool detach = false}) async {
    if (strict && effectiveStrictExitSeconds == 60 && exitRemaining > 0) {
      throw StateError('Wait for the exit countdown.');
    }
    if (localMode) {
      localExitAt = null;
      pendingExitAction = null;
      (await local.stopActiveRun(
        reason: StopFocusReason.interrupted,
      )).getOrThrow();
      await _readLocal();
      if (detach) detached = true;
      localRevision++;
      await persist();
    } else if (detach && !online) {
      if (effectiveStrictExitSeconds == 60 && exitRemaining > 0) {
        throw StateError('Wait for the exit countdown.');
      }
      detached = true;
      localExitAt = null;
      pendingExitAction = null;
      localRevision++;
      await persist();
    } else {
      await command(detach ? 'detach' : 'requestStop', {'confirmed': true});
      pendingExitAction = null;
      notify();
    }
  }

  Future<bool> detachDevice({bool confirmed = false}) async {
    if (detached) return true;
    if (localMode || !online) {
      await _guardLocal('detach', confirmed: confirmed);
      detached = true;
      localRevision++;
      await persist();
      return true;
    }
    if (remote != null && session != null) {
      await command('detach', {'confirmed': confirmed});
    }
    detached = true;
    await persist();
    return true;
  }

  Future<void> dispose() async {
    disposed = true;
    _poll?.cancel();
    _exitTimer?.cancel();
    await _runSub?.cancel();
    await _intervalSub?.cancel();
    await _changes.close();
  }

  // Subscribe before the snapshot so startup hydration cannot fall between them.
  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.multi((controller) {
    final subscription = changes.listen(
      (_) => controller.add(activeRun),
      onDone: controller.close,
    );
    controller.add(activeRun);
    controller.onCancel = subscription.cancel;
  });

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() =>
      Stream.multi((controller) {
        final subscription = changes.listen(
          (_) => controller.add(activeInterval),
          onDone: controller.close,
        );
        controller.add(activeInterval);
        controller.onCancel = subscription.cancel;
      });

  @override
  Stream<List<FocusPresetItem>> watchPresets() async* {
    List<FocusPresetItem> project(List<FocusPresetItem> values) {
      final snapshot = sharedActive && !localMode
          ? (session?['preset'])
          : localPreset;
      if (snapshot is! Map || activeRun == null) return values;
      final id = activeRun!.presetId, stamp = now();
      final stored = values.where((p) => p.id == id).firstOrNull;
      final p = FocusPresetItem(
        id: id,
        userId: owner,
        name: snapshot['name'] as String? ?? 'Focus',
        workSeconds: snapshot['workSeconds'] as int? ?? 1500,
        shortBreakSeconds: snapshot['shortBreakSeconds'] as int? ?? 300,
        longBreakSeconds: snapshot['longBreakSeconds'] as int? ?? 900,
        intervalsBeforeLongBreak:
            snapshot['intervalsBeforeLongBreak'] as int? ?? 4,
        autoStartBreaks: snapshot['autoStartBreaks'] == true,
        autoStartWork: snapshot['autoStartWork'] == true,
        allowPause: snapshot['allowPause'] != false,
        strictMode: snapshot['strictMode'] == true,
        isDefault: stored?.isDefault ?? false,
        distractionProfileConfigured:
            stored?.distractionProfileConfigured ?? false,
        distractionProfileId: stored?.distractionProfileId,
        createdAt: stamp,
        updatedAt: stamp,
      );
      return [
        for (final v in values)
          if (v.id != id) v,
        p,
      ];
    }

    final updates = StreamController<List<FocusPresetItem>>();
    var values = <FocusPresetItem>[];
    final presets = local.watchPresets().listen((v) {
      values = v;
      updates.add(project(values));
    });
    final sessions = changes.listen((_) => updates.add(project(values)));
    try {
      yield* updates.stream;
    } finally {
      await presets.cancel();
      await sessions.cancel();
      await updates.close();
    }
  }

  @override
  Stream<List<FocusRunItem>> watchRunsForTask(String id) =>
      local.watchRunsForTask(id);
  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String id) =>
      local.watchIntervalsForTask(id);
  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String id) =>
      local.watchIntervalsForRun(id);
  @override
  Stream<FocusDailyStats> watchDailyStats(DateTime d) =>
      local.watchDailyStats(d);
  @override
  Future<Result<String>> createPreset(CreateFocusPresetInput i) =>
      local.createPreset(i);
  @override
  Future<Result<void>> updatePreset(String id, UpdateFocusPresetInput i) =>
      local.updatePreset(id, i);
  @override
  Future<Result<void>> setPresetDistractionProfile(
    String presetId,
    String? profileId,
  ) => Result.capture(() async {
    if (profileId != null &&
        !profiles.any((p) => p.id == profileId && !p.isDeleted)) {
      throw StateError('Blocking profile is unavailable.');
    }
    (await local.setPresetDistractionProfile(presetId, profileId)).getOrThrow();
  });
  @override
  Future<Result<void>> deletePreset(String id) => local.deletePreset(id);
  @override
  Future<Result<void>> setDefaultPreset(String id) =>
      local.setDefaultPreset(id);
  @override
  Future<Result<void>> changeActiveRunPreset(String id) => Result.capture(
    () async {
      if (localMode) {
        await _guardLocal('preset');
        (await local.changeActiveRunPreset(id)).getOrThrow();
        final values = await local.watchPresets().first;
        final p = values.where((p) => p.id == id).firstOrNull;
        if (p != null) {
          if (!_localStrict && p.strictMode) strictExitSeconds = 60;
          _localStrict = p.strictMode;
          localPreset = presetWire(p);
        }
        await _readLocal();
        localRevision++;
        await persist();
      } else if (sharedActive) {
        final presets = await local.watchPresets().first;
        final p = presets.where((p) => p.id == id).firstOrNull;
        if (strict) {
          await command('requestStop');
          return;
        }
        if (p != null) await command('changePreset', {'preset': presetWire(p)});
      } else {
        (await local.changeActiveRunPreset(id)).getOrThrow();
      }
    },
  );
  @override
  Future<Result<String>> startRun(
    StartFocusRunInput input, {
    DateTime? now,
  }) => Result.capture(() async {
    if (sharedActive && !localMode && (online || !detached)) {
      throw StateError('A shared Focus is already active.');
    }
    if (localMode && activeRun != null) await _guardLocal('start');
    final presets = await local.watchPresets().first;
    final p = selectedFocusPresetOrDefault(presets, input.presetId);
    final profileId = p?.effectiveDistractionProfileId(selectedProfileId);
    if (profileId != null &&
        !profiles.any((p) => p.id == profileId && !p.isDeleted)) {
      throw StateError(
        'The assigned blocking profile is unavailable. Reload profiles or choose another profile.',
      );
    }
    if (online && remote != null && p != null) {
      await command('start', {
        'preset': presetWire(p),
        'taskId': input.taskId,
        'projectId': input.projectId,
        'targetWorkIntervals': input.targetWorkIntervals,
        'note': input.note,
        'profileId': profileId,
        'strictExitSeconds': strictExitSeconds,
      });
      localMode = false;
      detached = false;
      await persist();
      return session!['id'] as String;
    }
    if (session?['id'] is String) _rememberServerRun(session!['id']);
    final id = (await local.startRun(input, now: now)).getOrThrow();
    localProfileId = profileId;
    _localStrict = p?.strictMode ?? false;
    localPreset = p == null ? null : presetWire(p);
    detached = false;
    localMode = true;
    await _readLocal();
    localRevision++;
    await persist();
    return id;
  });
  Future<Result<void>> _act(
    String action,
    Future<Result<void>> Function() fallback, {
    bool destructive = false,
  }) => Result.capture(() async {
    if (localMode || remote == null) {
      if (destructive) await _guardLocal(action);
      (await fallback()).getOrThrow();
      await _readLocal();
      localRevision++;
      await persist();
    } else if (sharedActive) {
      final previousSession = session, previousConfirmation = _lastConfirmedAt;
      try {
        await command(destructive && strict ? 'requestStop' : action);
      } on StateError catch (e) {
        // Expiry can advance the server before the completion command checks its revision.
        if (action != 'complete' ||
            e.message != 'revision_conflict' ||
            previousSession?['interval']?['id'] ==
                session?['interval']?['id']) {
          rethrow;
        }
      } finally {
        await _autoStartReady(previousSession, previousConfirmation);
      }
    }
  });
  @override
  Future<Result<void>> startReadyInterval() =>
      _act('startReady', local.startReadyInterval);
  @override
  Future<Result<void>> pauseActiveInterval({DateTime? now}) =>
      _act('pause', () => local.pauseActiveInterval(now: now));
  @override
  Future<Result<void>> resumeActiveInterval({DateTime? now}) =>
      _act('resume', () => local.resumeActiveInterval(now: now));
  @override
  Future<Result<void>> restartActiveInterval({DateTime? now}) => _act(
    'restart',
    () => local.restartActiveInterval(now: now),
    destructive: true,
  );
  @override
  Future<Result<void>> completeActiveInterval({DateTime? now}) => _act(
    'complete',
    () => local.completeActiveInterval(now: now),
    destructive:
        activeInterval != null &&
        calculateRemaining(
              now: now ?? this.now(),
              startedAt: activeInterval!.startedAt,
              plannedSeconds: activeInterval!.plannedSeconds,
              pausedTotalSeconds: activeInterval!.pausedTotalSeconds,
              pausedAt: activeInterval!.pausedAt,
            ).inSeconds >
            0,
  );
  @override
  Future<Result<void>> skipActiveInterval({DateTime? now}) =>
      _act('skip', () => local.skipActiveInterval(now: now), destructive: true);
  @override
  Future<Result<void>> stopActiveRun({
    required StopFocusReason reason,
    DateTime? now,
  }) => _act(
    'requestStop',
    () => local.stopActiveRun(reason: reason, now: now),
    destructive: true,
  );
  @override
  Future<Result<void>> logDistraction({required String runId, String? note}) =>
      localMode
      ? local.logDistraction(runId: runId, note: note)
      : Future.value(const Result.ok(null));
}
