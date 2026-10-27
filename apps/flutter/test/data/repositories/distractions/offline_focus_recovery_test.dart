import 'dart:async';
import 'package:pomodoist/config/distraction_repository.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/distractions/live_focus_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository_impl.dart';
import 'package:pomodoist/data/services/distractions/focus_wire.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/focus_adoption_service.dart';
import 'package:pomodoist/data/services/local/focus_local_service.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Notifications extends NotificationScheduler {
  @override
  Future<void> cancelFocusNotification() async {}
  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {}
}

class FailingOutbox extends Fake implements OutboxService {
  @override
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
    DateTime? availableAt,
  }) async => throw StateError('outbox full');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late DriftFocusRepository local;
  late LiveFocusRepository focus;
  late Set<String> serverOwned;
  late SharedPreferences prefs;
  Map<String, dynamic>? authoritative;
  var loseAdoption = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    serverOwned = {};
    authoritative = null;
    loseAdoption = false;
    local = DriftFocusRepository(
      db,
      DriftOutboxService(db),
      Notifications(),
      serverOwnedRunIds: serverOwned,
    );
    focus = LiveFocusRepository(
      local: local,
      owner: 'owner',
      deviceId: 'device',
      preferences: prefs,
      onServerOwned: serverOwned.add,
      onAdopted: (id) => acknowledgeAdoptedFocusRun(db, id),
      remote: (command) async {
        if (command['action'] == 'start') {
          final payload = command['payload'] as Map;
          final adopt = payload['adopt'] as Map;
          authoritative = {
            'id': adopt['run']['id'],
            'revision': 1,
            'run': adopt['run'],
            'interval': adopt['interval'],
            'preset': payload['preset'],
          };
          if (loseAdoption) {
            throw TimeoutException('response lost after commit');
          }
        }
        return {'session': authoritative};
      },
    );
    await focus.start();
  });
  tearDown(() async {
    await focus.dispose();
    await db.close();
  });

  test('binding transaction rolls back when enqueue fails', () async {
    final repository = DriftFocusRepository(
      db,
      FailingOutbox(),
      Notifications(),
    );
    final before = (await repository.watchPresets().first).first;
    expect(
      await repository.setPresetDistractionProfile(before.id, 'study'),
      isA<Failure<void>>(),
    );
    final after = (await repository.watchPresets().first).firstWhere(
      (p) => p.id == before.id,
    );
    expect(after.distractionProfileConfigured, false);
    expect(after.distractionProfileId, isNull);
    expect(after.updatedAt, before.updatedAt);
  });

  for (final reason in StopFocusReason.values) {
    test(
      'profile can be selected again after local Focus ends: $reason',
      () async {
        final preset = (await local.watchPresets().first).first;
        focus.online = false;
        final commands = CoordinatedDistractionRepository(
          focus,
          protection: () => null,
          classifyResource: (resource) async => resource,
        );
        await commands.saveProfile(
          DistractionProfile.fromJson({'id': 'custom', 'name': 'Custom'}),
        );
        (await focus.setPresetDistractionProfile(
          preset.id,
          'custom',
        )).getOrThrow();
        (await focus.startRun(
          StartFocusRunInput(presetId: preset.id),
        )).getOrThrow();
        expect(commands.state.active, true);
        (await focus.stopActiveRun(reason: reason)).getOrThrow();
        expect(commands.state.active, false);
        expect(await focus.watchActiveRun().first, isNull);
        (await focus.setPresetDistractionProfile(preset.id, null)).getOrThrow();
        final saved = (await focus.watchPresets().first).firstWhere(
          (p) => p.id == preset.id,
        );
        expect(saved.distractionProfileId, isNull);
        expect(saved.distractionProfileConfigured, true);
      },
    );
  }

  for (final paused in [false, true]) {
    for (final profileId in <String?>['work', null]) {
      test(
        'next profile $profileId is saved without changing local Focus paused=$paused',
        () async {
          focus.online = false;
          final preset = (await local.watchPresets().first).first;
          (await focus.setPresetDistractionProfile(
            preset.id,
            'study',
          )).getOrThrow();
          (await focus.startRun(
            StartFocusRunInput(presetId: preset.id),
          )).getOrThrow();
          if (paused) (await focus.pauseActiveInterval()).getOrThrow();
          final runId = focus.activeRun!.id;
          final revision = focus.localRevision;
          (await focus.setPresetDistractionProfile(
            preset.id,
            profileId,
          )).getOrThrow();
          final saved = (await focus.watchPresets().first).firstWhere(
            (p) => p.id == preset.id,
          );
          expect(saved.distractionProfileConfigured, true);
          expect(saved.distractionProfileId, profileId);
          expect(focus.activeRun!.id, runId);
          expect(focus.envelope['session']['profileId'], 'study');
          expect(focus.selectedProfile?.id, 'study');
          expect(focus.localRevision, revision);
          expect(focus.pendingExitAction, isNull);
          (await focus.stopActiveRun(
            reason: StopFocusReason.stopped,
          )).getOrThrow();
          (await focus.startRun(
            StartFocusRunInput(presetId: preset.id),
          )).getOrThrow();
          expect(focus.envelope['session']['profileId'], profileId);
        },
      );
    }
  }

  test(
    'binding saves both fields without changing rhythm and queues synchronization',
    () async {
      final before = (await local.watchPresets().first).first;
      (await local.setPresetDistractionProfile(
        before.id,
        'study',
      )).getOrThrow();
      var saved = (await local.watchPresets().first).firstWhere(
        (p) => p.id == before.id,
      );
      expect(saved.distractionProfileConfigured, true);
      expect(saved.distractionProfileId, 'study');
      expect(saved.workSeconds, before.workSeconds);
      (await local.setPresetDistractionProfile(before.id, null)).getOrThrow();
      saved = (await local.watchPresets().first).firstWhere(
        (p) => p.id == before.id,
      );
      expect(saved.distractionProfileConfigured, true);
      expect(saved.distractionProfileId, isNull);
      expect(
        (await db.select(db.syncCommands).get()).where(
          (c) => c.type == 'focus.preset.update',
        ),
        isNotEmpty,
      );
      expect(
        await local.setPresetDistractionProfile('missing', null),
        isA<Failure<void>>(),
      );
    },
  );

  for (final profileId in <String?>['study', null]) {
    test(
      'explicit $profileId survives local restart and adoption instead of global work',
      () async {
        focus.selectedProfileId = 'work';
        final preset = (await local.watchPresets().first).first;
        (await focus.setPresetDistractionProfile(
          preset.id,
          profileId,
        )).getOrThrow();
        focus.online = false;
        (await focus.startRun(
          StartFocusRunInput(presetId: preset.id),
        )).getOrThrow();
        expect(focus.envelope['session']['profileId'], profileId);
        expect(
          await focus.setPresetDistractionProfile(preset.id, 'work'),
          isA<Success<void>>(),
        );
        await focus.dispose();
        focus = LiveFocusRepository(
          local: local,
          owner: 'owner',
          deviceId: 'device',
          preferences: prefs,
          remote: (command) async {
            if (command['action'] == 'read') return {'session': null};
            final payload = command['payload'] as Map;
            expect(payload['profileId'], profileId);
            expect(
              (payload['preset'] as Map).containsKey(
                'distractionProfileConfigured',
              ),
              false,
            );
            final adopt = payload['adopt'] as Map;
            return {
              'session': {
                'id': adopt['run']['id'],
                'run': adopt['run'],
                'interval': adopt['interval'],
                'preset': payload['preset'],
                'profileId': payload['profileId'],
              },
            };
          },
        );
        await focus.start();
        expect(focus.localMode, false);
        expect(focus.session?['profileId'], profileId);
        expect(focus.selectedProfile?.id, profileId);
      },
    );
  }

  test(
    'missing assigned profile blocks start rather than removing protection',
    () async {
      final preset = (await local.watchPresets().first).first;
      (await local.setPresetDistractionProfile(
        preset.id,
        'deleted',
      )).getOrThrow();
      expect(
        await focus.startRun(StartFocusRunInput(presetId: preset.id)),
        isA<Failure<String>>(),
      );
      expect(focus.activeRun, isNull);
      focus.profiles.add(
        DistractionProfile.fromJson({'id': 'deleted', 'name': 'Loaded'}),
      );
      focus.online = false;
      expect(
        await focus.startRun(StartFocusRunInput(presetId: preset.id)),
        isA<Success<String>>(),
      );
    },
  );

  test(
    'lost adoption response is acknowledged on the next authoritative read',
    () async {
      focus.online = false;
      final id = (await focus.startRun(
        const StartFocusRunInput(),
      )).getOrThrow();
      expect(focus.localMode, true);
      loseAdoption = true;
      await focus.refresh();
      expect(focus.localMode, true);
      expect(authoritative?['id'], id);
      await focus.refresh();
      expect(focus.localMode, false);
      expect(focus.adoptedRunIds, contains(id));
      expect(serverOwned, contains(id));
      final pending = await (db.select(db.syncCommands)).get();
      expect(
        pending.where(
          (c) =>
              c.clientId == id && !['synced', 'compacted'].contains(c.status),
        ),
        isEmpty,
      );
      expect(
        (await db.select(db.focusRuns).get()).where((r) => r.id == id),
        hasLength(1),
      );
    },
  );

  test(
    'explicit offline detach permits local start without modifying shared shadow',
    () async {
      final shadowId = (await local.startRun(
        const StartFocusRunInput(),
      )).getOrThrow();
      final run = await local.watchActiveRun().first;
      final interval = await local.watchActiveInterval().first;
      authoritative = {
        'id': shadowId,
        'revision': 3,
        'run': runWire(run!),
        'interval': intervalWire(interval!),
        'preset': {'strictMode': false},
      };
      await acknowledgeAdoptedFocusRun(db, shadowId);
      await focus.refresh();
      focus.localMode = false;
      focus.online = false;
      expect(
        await focus.startRun(const StartFocusRunInput()),
        isA<Failure<String>>(),
      );
      expect(await focus.detachDevice(), true);
      final before = (await db.select(db.focusRuns).get()).firstWhere(
        (r) => r.id == shadowId,
      );
      await FocusLocalService(
        db,
        serverOwnedRunIds: serverOwned,
      ).reassignActiveRunsPreset(
        before.presetId,
        'replacement',
        DateTime.now().toUtc(),
      );
      final failed = await focus.startRun(
        const StartFocusRunInput(taskId: 'missing'),
      );
      expect(failed, isA<Failure<String>>());
      expect(focus.localMode, false);
      expect(focus.detached, true);
      final localId = (await focus.startRun(
        const StartFocusRunInput(),
      )).getOrThrow();
      expect(localId, isNot(shadowId));
      expect(focus.localMode, true);
      expect(focus.activeRun?.id, localId);
      final after = (await db.select(db.focusRuns).get()).firstWhere(
        (r) => r.id == shadowId,
      );
      expect(after, before);
      final pending = await db.select(db.syncCommands).get();
      expect(
        pending.where(
          (c) =>
              c.clientId == shadowId &&
              !['synced', 'compacted'].contains(c.status),
        ),
        isEmpty,
      );
      await focus.refresh();
      expect(focus.conflict, true);
      expect(focus.localMode, true);
      expect(authoritative?['id'], shadowId);
    },
  );
  test(
    'restart acknowledges adoption persisted before local takeover',
    () async {
      focus.online = false;
      final id = (await focus.startRun(
        const StartFocusRunInput(),
      )).getOrThrow();
      loseAdoption = true;
      await focus.refresh();
      await focus.command('read');
      expect(focus.localMode, true);
      expect(focus.pendingAdoptionRunId, id);
      await focus.dispose();
      serverOwned.clear();
      focus = LiveFocusRepository(
        local: local,
        owner: 'owner',
        deviceId: 'device',
        preferences: prefs,
        onServerOwned: serverOwned.add,
        onAdopted: (id) => acknowledgeAdoptedFocusRun(db, id),
        remote: (_) async => {'session': authoritative},
      );
      await focus.start();
      expect(focus.localMode, false);
      expect(focus.activeRun?.id, id);
      expect(focus.pendingAdoptionRunId, isNull);
      expect(focus.adoptedRunIds, contains(id));
      final pending = await db.select(db.syncCommands).get();
      expect(
        pending.where(
          (c) =>
              c.clientId == id && !['synced', 'compacted'].contains(c.status),
        ),
        isEmpty,
      );
    },
  );
  test(
    'older shared shadows stay immutable after a newer session and offline restart',
    () async {
      final id = (await local.startRun(
        const StartFocusRunInput(),
      )).getOrThrow();
      final run = await local.watchActiveRun().first;
      final interval = await local.watchActiveInterval().first;
      authoritative = {
        'id': id,
        'revision': 1,
        'run': runWire(run!),
        'interval': intervalWire(interval!),
        'preset': {'strictMode': false},
      };
      await acknowledgeAdoptedFocusRun(db, id);
      focus.localMode = false;
      await focus.command('read');
      authoritative = {
        ...authoritative!,
        'id': 'newer',
        'run': {...runWire(run), 'id': 'newer'},
      };
      await focus.command('read');
      await focus.dispose();
      serverOwned.clear();
      focus = LiveFocusRepository(
        local: local,
        owner: 'owner',
        deviceId: 'device',
        preferences: prefs,
        onServerOwned: serverOwned.add,
        remote: (_) async => throw TimeoutException('offline'),
      );
      await focus.start();
      expect(serverOwned, containsAll([id, 'newer']));
      expect(focus.localMode, false);
      await focus.detachDevice();
      final localId = (await focus.startRun(
        const StartFocusRunInput(),
      )).getOrThrow();
      expect(focus.activeRun?.id, localId);
      final shadow = (await db.select(db.focusRuns).get()).firstWhere(
        (r) => r.id == id,
      );
      expect(shadow.status, 'active');
      final pending = await db.select(db.syncCommands).get();
      expect(
        pending.where(
          (c) =>
              c.clientId == id && !['synced', 'compacted'].contains(c.status),
        ),
        isEmpty,
      );
    },
  );
}
