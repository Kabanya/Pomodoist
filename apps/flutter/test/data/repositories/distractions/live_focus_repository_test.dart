import 'package:pomodoist/domain/models/focus/focus_models.dart';
import '../../../../testing/fakes/fake_focus_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/distractions/live_focus_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';

class Local extends Fake implements FocusRepository {}

Map<String, dynamic> session(DateTime time, {bool paused = false}) => {
  'id': 'run',
  'revision': 2,
  'profileId': 'work',
  'preset': {'strictMode': true},
  'protectionExpiresAt': time.add(const Duration(minutes: 5)).toIso8601String(),
  'run': {
    'id': 'run',
    'userId': 'u',
    'presetId': 'classic',
    'status': 'active',
    'startedAt': time.toIso8601String(),
    'createdAt': time.toIso8601String(),
    'updatedAt': time.toIso8601String(),
    'targetWorkIntervals': 4,
    'completedWorkIntervals': 0,
  },
  'interval': {
    'id': 'i',
    'runId': 'run',
    'type': 'work',
    'status': paused ? 'paused' : 'running',
    'plannedSeconds': 1500,
    'startedAt': time.toIso8601String(),
    'pausedAt': paused ? time.toIso8601String() : null,
    'pausedTotalSeconds': 0,
    'sequenceNumber': 1,
    'createdAt': time.toIso8601String(),
    'updatedAt': time.toIso8601String(),
  },
};
void main() {
  for (final paused in [false, true]) {
    for (final profileId in <String?>['study', null]) {
      test(
        'next profile $profileId can be saved during shared Focus paused=$paused',
        () async {
          final time = DateTime.utc(2026, 10, 26);
          final local = FakeFocusRepository();
          final repo = LiveFocusRepository(
            local: local,
            owner: 'u',
            deviceId: 'd',
            preferences: null,
            clock: () => time,
            remote: (_) async =>
                throw StateError('must not change shared Focus'),
          );
          addTearDown(repo.dispose);
          repo.profiles = [
            for (final id in ['work', 'study'])
              DistractionProfile.fromJson({'id': id, 'name': id}),
          ];
          repo.session = session(time, paused: paused);
          final before = repo.session;
          final protection = repo.protection;
          expect(protection, isNotNull);
          (await repo.setPresetDistractionProfile(
            'classic',
            profileId,
          )).getOrThrow();
          expect(local.setPresetDistractionProfileCalls.single, (
            presetId: 'classic',
            profileId: profileId,
          ));
          expect(repo.session, same(before));
          expect(repo.selectedProfile?.id, 'work');
          expect(repo.protection, protection);
          expect(repo.pendingExitAction, isNull);
        },
      );
    }
  }

  for (final configured in [false, true]) {
    for (final binding in <String?>['study', null]) {
      for (final input in [
        const StartFocusRunInput(),
        const StartFocusRunInput(presetId: 'classic'),
        const StartFocusRunInput(
          presetId: 'classic',
          taskId: 'task',
          projectId: 'project',
        ),
      ]) {
        test(
          'shared start resolves configured=$configured binding=$binding task=${input.taskId}',
          () async {
            final time = DateTime.utc(2026, 10, 26);
            final local = FakeFocusRepository()
              ..presets = [
                FocusPresetItem(
                  id: 'classic',
                  userId: 'u',
                  name: 'Classic',
                  workSeconds: 1500,
                  shortBreakSeconds: 300,
                  longBreakSeconds: 900,
                  intervalsBeforeLongBreak: 4,
                  autoStartBreaks: false,
                  autoStartWork: false,
                  allowPause: true,
                  strictMode: false,
                  isDefault: true,
                  createdAt: time,
                  updatedAt: time,
                  distractionProfileConfigured: configured,
                  distractionProfileId: binding,
                ),
              ];
            Map? payload;
            final repo = LiveFocusRepository(
              local: local,
              owner: 'u',
              deviceId: 'd',
              preferences: null,
              remote: (command) async {
                payload = command['payload'] as Map;
                return {
                  'session': {
                    ...session(time),
                    'profileId': payload!['profileId'],
                  },
                };
              },
            );
            addTearDown(repo.dispose);
            repo.online = true;
            repo.selectedProfileId = 'work';
            repo.profiles = [
              for (final id in ['work', 'study'])
                DistractionProfile.fromJson({'id': id, 'name': id}),
            ];
            (await repo.startRun(input)).getOrThrow();
            expect(payload!['profileId'], configured ? binding : 'work');
            expect(
              (payload!['preset'] as Map).containsKey(
                'distractionProfileConfigured',
              ),
              false,
            );
            expect(
              (payload!['preset'] as Map).containsKey('distractionProfileId'),
              false,
            );
            expect(repo.selectedProfile?.id, configured ? binding : 'work');
            expect(local.startRunCalls, isEmpty);
          },
        );
      }
    }
  }

  test(
    'shared protection expires while disconnected and cannot renew paused lease',
    () async {
      var time = DateTime.utc(2026, 10, 26);
      final repo = LiveFocusRepository(
        local: Local(),
        remote: null,
        owner: 'u',
        deviceId: 'd',
        preferences: null,
        clock: () => time,
      );
      repo.profiles = [
        DistractionProfile.fromJson({
          'id': 'work',
          'name': 'Work',
          'blockedCategories': ['video'],
        }),
      ];
      repo.session = session(time, paused: true);
      expect(repo.protection, isNotNull);
      time = time.add(const Duration(minutes: 6));
      expect(repo.protection, isNull);
      await repo.dispose();
    },
  );
  test(
    'stale commands accept newest revision but fail instead of local fallback',
    () async {
      final time = DateTime.utc(2026, 10, 26);
      final repo = LiveFocusRepository(
        local: Local(),
        owner: 'u',
        deviceId: 'd',
        preferences: null,
        clock: () => time,
        remote: (command) async => {
          'session': {...session(time), 'revision': 3},
          'code': 'revision_conflict',
        },
      );
      repo.session = session(time);
      await expectLater(repo.command('pause'), throwsStateError);
      expect(repo.session!['revision'], 3);
      expect(repo.localMode, false);
      await repo.dispose();
    },
  );
  test(
    'commands are serialized using the latest acknowledged revision',
    () async {
      final revisions = <int>[];
      var revision = 2;
      final time = DateTime.utc(2026, 10, 26);
      final repo = LiveFocusRepository(
        local: Local(),
        owner: 'u',
        deviceId: 'd',
        preferences: null,
        clock: () => time,
        remote: (command) async {
          revisions.add(command['expectedRevision']);
          await Future<void>.delayed(Duration.zero);
          return {
            'session': {...session(time), 'revision': ++revision},
          };
        },
      );
      repo.session = session(time);
      await Future.wait([repo.command('pause'), repo.command('resume')]);
      expect(revisions, [2, 3]);
      await repo.dispose();
    },
  );

  test('response latency never extends the last confirmed lease', () async {
    final sent = DateTime.utc(2026, 10, 26);
    var time = sent;
    final repo = LiveFocusRepository(
      local: Local(),
      owner: 'u',
      deviceId: 'd',
      preferences: null,
      clock: () => time,
      remote: (_) async {
        time = sent.add(const Duration(seconds: 20));
        return {
          'serverNow': sent.toIso8601String(),
          'session': session(sent, paused: true),
        };
      },
    );
    repo.profiles = [
      DistractionProfile.fromJson({
        'id': 'work',
        'name': 'Work',
        'blockedCategories': ['video'],
      }),
    ];
    await repo.command('read');
    expect(
      DateTime.parse(repo.protection!['expiresAt']),
      sent.add(const Duration(minutes: 5)),
    );
    time = sent.add(const Duration(minutes: 5));
    expect(repo.protection, isNull);
    expect(repo.guardExpiry, sent.add(const Duration(minutes: 5)));
    await repo.dispose();
  });
  test(
    'natural expiry revision conflict still starts an eligible ready interval',
    () async {
      final time = DateTime.utc(2026, 10, 26);
      final old = session(time.subtract(const Duration(minutes: 25)));
      old['protectionExpiresAt'] = time.toIso8601String();
      final ready = {
        ...old,
        'revision': 3,
        'preset': {'strictMode': true, 'autoStartBreaks': true},
        'interval': {
          ...old['interval'] as Map,
          'id': 'next',
          'type': 'shortBreak',
          'status': 'ready',
          'startedAt': time.toIso8601String(),
        },
      };
      final actions = <String>[];
      final repo = LiveFocusRepository(
        local: Local(),
        owner: 'u',
        deviceId: 'd',
        preferences: null,
        clock: () => time,
        remote: (command) async {
          actions.add(command['action']);
          return {
            'session': command['action'] == 'read' ? old : ready,
            'code': command['action'] == 'complete'
                ? 'revision_conflict'
                : 'ok',
          };
        },
      );
      repo.session = old;
      await repo.command('read');
      actions.clear();
      (await repo.completeActiveInterval()).getOrThrow();
      expect(actions, ['complete', 'startReady']);
      await repo.dispose();
    },
  );
  test(
    'strict destructive controls route through shared exit policy',
    () async {
      final time = DateTime.utc(2026, 10, 26);
      final actions = <String>[];
      final repo = LiveFocusRepository(
        local: Local(),
        owner: 'u',
        deviceId: 'd',
        preferences: null,
        clock: () => time,
        remote: (command) async {
          actions.add(command['action']);
          return {
            'session': {
              ...session(time),
              'strictExitSeconds': 60,
              'exitRequestedAt': time.toIso8601String(),
            },
            'code': 'strict_exit_pending',
          };
        },
      );
      repo.session = session(time);
      await repo.skipActiveInterval();
      expect(actions, ['requestStop']);
      expect(repo.exitRemaining, 60);
      expect(repo.pendingExitAction, 'requestStop');
      await repo.dispose();
    },
  );
}
