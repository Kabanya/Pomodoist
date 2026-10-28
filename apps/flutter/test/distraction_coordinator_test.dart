import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/distraction_protection_coordinator.dart';
import 'package:pomodoist/config/distraction_repository.dart';
import 'package:pomodoist/data/repositories/distractions/live_focus_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/data/services/platform/distraction_native_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import '../testing/fakes/fake_focus_repository.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native completion publishes status and error changes to Blocking',
    () async {
      final focus = LiveFocusRepository(
        local: FakeFocusRepository(),
        remote: null,
        owner: 'local',
        deviceId: 'desktop',
        preferences: null,
      );
      const channel = MethodChannel('test/native-status-notifications');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final cleared = Completer<void>();
      var fail = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'clearProtection') {
          if (fail) throw PlatformException(code: 'native-unavailable');
          await cleared.future;
        }
        return null;
      });
      final native = DistractionNativeGateway(channel: channel);
      final protection = ProtectionCoordinator(
        focus: focus,
        native: native,
        flavor: 'development',
        preferences: null,
        taskTitle: (_) async => null,
      )..nativeApplied = true;
      final repository = CoordinatedDistractionRepository(
        focus,
        protection: () => protection,
        classifyResource: (resource) async => resource,
      );
      final observed = <({bool applied, String? error})>[];
      final subscription = repository.changes.listen((_) {
        final state = repository.state;
        observed.add((applied: state.nativeApplied, error: state.error));
      });
      try {
        final pending = protection.apply();
        await Future<void>.delayed(Duration.zero);
        expect(observed, isEmpty);
        expect(repository.state.nativeApplied, isTrue);
        cleared.complete();
        await pending;
        await Future<void>.delayed(Duration.zero);
        expect(observed, [(applied: false, error: null)]);

        await protection.apply();
        await Future<void>.delayed(Duration.zero);
        expect(observed, hasLength(1));

        fail = true;
        await protection.apply();
        await Future<void>.delayed(Duration.zero);
        expect(observed.last.error, contains('native-unavailable'));
        expect(observed, hasLength(2));

        fail = false;
        await protection.apply();
        await Future<void>.delayed(Duration.zero);
        expect(observed.last, (applied: false, error: null));
        expect(observed, hasLength(3));
      } finally {
        await subscription.cancel();
        await protection.dispose();
        await native.dispose();
        await focus.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );

  test(
    'paired reads preserve cached shared Focus while cloud is unavailable',
    () async {
      final time = DateTime.utc(2026, 10, 27);
      final stamp = time.toIso8601String();
      final focus = LiveFocusRepository(
        local: FakeFocusRepository(),
        remote: (_) async => throw const SocketException('cloud unavailable'),
        owner: 'account',
        deviceId: 'desktop',
        preferences: null,
        clock: () => time,
      );
      focus.profiles = [
        DistractionProfile.fromJson({'id': 'work', 'name': 'Work'}),
      ];
      focus.session = {
        'id': 'shared',
        'revision': 7,
        'profileId': 'work',
        'preset': {'strictMode': false},
        'protectionExpiresAt': time
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'run': {
          'id': 'shared',
          'presetId': 'classic',
          'status': 'active',
          'startedAt': stamp,
          'createdAt': stamp,
          'updatedAt': stamp,
          'targetWorkIntervals': 4,
          'completedWorkIntervals': 0,
        },
        'interval': {
          'id': 'interval',
          'runId': 'shared',
          'type': 'work',
          'status': 'running',
          'plannedSeconds': 1500,
          'pausedTotalSeconds': 0,
          'sequenceNumber': 1,
          'startedAt': stamp,
          'createdAt': stamp,
          'updatedAt': stamp,
        },
      };
      const channel = MethodChannel('test/cached-distractions');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'supported': true, 'platform': 'macos'},
      );
      final protection = ProtectionCoordinator(
        focus: focus,
        native: DistractionNativeGateway(channel: channel),
        flavor: 'development',
        bridgePort: 0,
        preferences: null,
        taskTitle: (_) async => null,
      );
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final client = HttpClient();
      var token = '';
      Future<Map> request(String path, Map body) async {
        final r = await client.postUrl(
          Uri.parse('http://127.0.0.1:${protection.bridge!.port}$path'),
        );
        r.headers.set(
          'Origin',
          'chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );
        if (token.isNotEmpty) r.headers.set('Authorization', 'Bearer $token');
        r.headers.contentType = ContentType.json;
        r.write(jsonEncode(body));
        final response = await r.close();
        expect(response.statusCode, 200);
        return jsonDecode(await response.transform(utf8.decoder).join()) as Map;
      }

      try {
        await protection.start();
        token = (await request('/pair', {
          'code': protection.bridge!.pair(),
          'deviceId': 'browser',
          'flavor': 'development',
        }))['token'];
        final result = await request('/command', {
          'action': 'read',
          'requestId': 'offline-read',
        });
        expect(result['session']['id'], 'shared');
        expect(result['session']['revision'], 7);
        expect(result['protection']['sessionId'], 'shared');
        expect(
          result['protection']['expiresAt'],
          time.add(const Duration(minutes: 5)).toIso8601String(),
        );
      } finally {
        client.close(force: true);
        HttpOverrides.global = previousOverrides;
        await protection.dispose();
        await focus.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
  test(
    'paired offline Chrome preserves preset, strict exit and revisions across restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureSeedData();
      final local = DriftFocusRepository(
        db,
        DriftOutboxService(db),
        Notifications(),
      );
      final focus = LiveFocusRepository(
        local: local,
        remote: null,
        owner: 'test',
        deviceId: 'desktop',
        preferences: prefs,
      );
      await focus.start();
      await Future<void>.delayed(Duration.zero);
      const channel = MethodChannel('test/distractions');
      final leases = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'capabilities') {
              return {
                'supported': true,
                'discovery': true,
                'platform': 'macos',
              };
            }
            if (call.method == 'setProtection') {
              leases.add(call.arguments as Map);
            }
            return null;
          });
      ProtectionCoordinator coordinator() => ProtectionCoordinator(
        focus: focus,
        native: DistractionNativeGateway(channel: channel),
        flavor: 'development',
        bridgePort: 0,
        preferences: prefs,
        taskTitle: (_) async => null,
      );
      var protection = coordinator();
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final client = HttpClient();
      var token = '';
      Future<Map> request(String path, Map body) async {
        final r = await client.postUrl(
          Uri.parse('http://127.0.0.1:${protection.bridge!.port}$path'),
        );
        r.persistentConnection = false;
        r.headers.set(
          'Origin',
          'chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );
        if (token.isNotEmpty) r.headers.set('Authorization', 'Bearer $token');
        r.headers.contentType = ContentType.json;
        r.write(jsonEncode(body));
        final response = await r.close();
        expect(response.statusCode, 200);
        return jsonDecode(await response.transform(utf8.decoder).join()) as Map;
      }

      Future<Map> command(
        String action,
        String id, {
        Map payload = const {},
        int? revision,
      }) => request('/command', {
        'action': action,
        'requestId': id,
        'expectedRevision': revision ?? focus.localRevision,
        'payload': payload,
      });
      try {
        await protection.start();
        final paired = await request('/pair', {
          'code': protection.bridge!.pair(),
          'deviceId': 'browser',
          'flavor': 'development',
        });
        token = paired['token'];
        final result = await command(
          'start',
          'start-1',
          payload: {
            'preset': {
              'id': 'classic',
              'name': 'Sprint',
              'workSeconds': 900,
              'shortBreakSeconds': 120,
              'longBreakSeconds': 600,
              'intervalsBeforeLongBreak': 3,
              'strictMode': true,
              'allowPause': true,
            },
            'strictExitSeconds': 0,
            'profileId': 'work',
            'targetWorkIntervals': 2,
            'note': 'test',
          },
        );
        await Future<void>.delayed(Duration.zero);
        expect(result['session']['preset']['workSeconds'], 900);
        expect(focus.activeInterval!.plannedSeconds, 900);
        expect(focus.strict, true);
        expect(focus.activeRun!.targetWorkIntervals, 2);
        expect(focus.activeRun!.note, 'test');
        expect(focus.selectedProfileId, 'work');
        final initial = focus.localRevision;
        final exit = await command('requestStop', 'exit-1');
        expect(exit['code'], 'strict_confirmation_required');
        expect(focus.localRevision, greaterThan(initial));
        final stale = await command(
          'cancelStop',
          'stale-cancel',
          revision: initial,
        );
        expect(stale['code'], 'revision_conflict');
        final requestedRevision = focus.localRevision;
        await protection.dispose();
        protection = coordinator();
        await protection.start();
        final duplicate = await command(
          'requestStop',
          'exit-1',
          revision: initial,
        );
        expect(duplicate['code'], 'strict_confirmation_required');
        expect(focus.localRevision, requestedRevision);
        await command('cancelStop', 'cancel-1');
        expect(focus.pendingExitAction, isNull);
        expect(focus.localRevision, greaterThan(requestedRevision));
        await protection.apply();
        expect(leases.last['active'], true);
        expect(leases.last['blockedApps'], isEmpty);
        await command('requestStop', 'exit-2');
        await command('requestStop', 'confirm-2', payload: {'confirmed': true});
        await Future<void>.delayed(Duration.zero);
        expect(focus.activeRun, isNull);
        Map<String, dynamic> preset(bool strict, {int seconds = 900}) => {
          'id': 'classic',
          'name': 'Sprint',
          'workSeconds': seconds,
          'shortBreakSeconds': 120,
          'longBreakSeconds': 600,
          'intervalsBeforeLongBreak': 3,
          'strictMode': strict,
          'allowPause': true,
        };
        await command(
          'start',
          'ordinary',
          payload: {
            'preset': preset(false),
            'strictExitSeconds': 0,
            'profileId': 'work',
          },
        );
        final beforeChange = focus.localRevision;
        await command(
          'changePreset',
          'to-strict',
          payload: {'preset': preset(true, seconds: 600)},
        );
        expect(focus.strict, true);
        expect(focus.effectiveStrictExitSeconds, 60);
        expect(focus.localPreset!['workSeconds'], 600);
        expect(focus.localRevision, greaterThan(beforeChange));
        final replacement = await command(
          'start',
          'bypass-start',
          payload: {
            'preset': preset(false),
            'strictExitSeconds': 0,
            'profileId': 'study',
          },
        );
        expect(replacement['code'], 'strict_exit_pending');
        expect(focus.strict, true);
        expect(focus.effectiveStrictExitSeconds, 60);
        expect(focus.selectedProfileId, 'work');
        expect(focus.localPreset!['workSeconds'], 600);
        expect(
          focus.activeRun!.presetId,
          replacement['session']['run']['presetId'],
        );
      } finally {
        client.close(force: true);
        HttpOverrides.global = previousOverrides;
        await protection.dispose();
        await focus.dispose();
        await db.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
}
