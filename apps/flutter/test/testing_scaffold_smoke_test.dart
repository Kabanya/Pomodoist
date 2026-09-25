import 'package:app_voice/app_voice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/sentry_observability.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';
import 'package:pomodoist/utils/result.dart';

import '../testing/fakes/fakes.dart';
import '../testing/models/models.dart';

void expectOk<T>(Result<T> result) => expect(result, isA<Success<T>>());

T valueOf<T>(Result<T> result) => (result as Success<T>).value;

class _Unstubbed extends StrictFake {}

void main() {
  group('testing scaffold smoke', () {
    group('fakes', () {
      test('strict fake rejects unstubbed members', () {
        expect(
          () => (_Unstubbed() as dynamic).anything(),
          throwsUnimplementedError,
        );
      });

      test('notifier doubles build and update state', () {
        expect(FakeBoolController().build(), isFalse);
        expect(FakeObjectController().build(), isNull);
        expect(FakeEntitlementController().build(), isFalse);

        final container = ProviderContainer(
          overrides: [
            NotifierProvider<FakeBoolController, bool>(FakeBoolController.new),
          ],
        );
        addTearDown(container.dispose);

        final provider =
            NotifierProvider<FakeBoolController, bool>(FakeBoolController.new);
        expect(container.read(provider), isFalse);
        container.read(provider.notifier).setValue(true);
        expect(container.read(provider), isTrue);
      });

      test('account client records calls and serves stubs', () async {
        final client = FakeAccountClient();

        expect(client.currentUserId, isNull);
        expect(client.currentEmail, isNull);
        expect(await client.authStateChanges().first, isFalse);
        expect((await client.accountAuthStateChanges().first).signedIn, isFalse);

        await client.signInWithEmail('person@example.com');
        expect(client.signInWithEmailCalls, hasLength(1));
        expect(
          client.signInWithEmailCalls.single.email,
          'person@example.com',
        );

        await client.signOut();
        expect(client.signOutCalls, hasLength(1));

        client.syncHints(appId: 'pomodoist');
        expect(client.syncHintsCalls, ['pomodoist']);

        await client.broadcastSyncHint(appId: 'pomodoist', deviceId: 'device-1');
        expect(client.broadcastSyncHintCalls.single.deviceId, 'device-1');

        expect(client.downloadedBytes, isEmpty);
      });

      test('account management repository answers and records', () async {
        final repository = FakeAccountManagementRepository();

        expect(repository.userId, 'user-1');
        expect(repository.email, 'person@example.com');
        expectOk(await repository.connectedAgents());
        expectOk(await repository.revokeAgent('client-1'));
        expect(repository.revokeAgentCalls, ['client-1']);
        expectOk(await repository.consent('client-1', approve: true));
        expect(repository.consentCalls.single.approve, isTrue);
        expectOk(await repository.updateNickname('Ada'));
        expect(repository.updateNicknameCalls, ['Ada']);
      });

      test('account session repository serves the current session', () async {
        final repository = FakeAccountSessionRepository();

        expect(repository.currentSession.userId, isNull);
        expect(repository.currentSession.generation, 0);
        expect((await repository.watchSession().first).generation, 0);
        expect(await repository.watchProfile().first, isNull);
        expectOk(await repository.refresh());
      });

      test('achievement repository replays achievements', () async {
        final repository = FakeAchievementRepository();

        expect(await repository.watchAchievements().first, isEmpty);
        final pending = await repository.takePendingAnnouncements(const []);
        expect(valueOf(pending), isEmpty);
      });

      test('billing repository records purchases and access', () async {
        final repository = FakeBillingRepository();

        expect(repository.isCancellation(Object()), isFalse);
        expect((await repository.watchAccess().first).loading, isFalse);
        expectOk(await repository.refresh());
        expect(repository.refreshCalls, hasLength(1));

        expect(repository.activeProductId, isNull);
        expect(repository.storeAvailable, isFalse);
        expect(repository.catalog.products, isEmpty);

        repository.setStoreAvailable(true);
        expect(repository.storeAvailable, isTrue);
        expect(repository.setStoreAvailableCalls, [true]);

        await repository.loadCatalog();
        expect(repository.loadCatalogCalls, hasLength(1));
        await repository.loadReturnOffers();
        expect(repository.loadReturnOffersCalls, hasLength(1));

        expect(valueOf(await repository.purchase('product')), isTrue);
        expect(repository.purchaseCalls.single.productId, 'product');

        repository.beginPurchase('product');
        expect(repository.pendingProductId, 'product');
        repository.cancelPurchase();
        expect(repository.pendingProductId, isNull);
      });

      test('billing store serves catalog and entitlements', () async {
        final store = FakeBillingStore();

        expect(await store.isAvailable(), isTrue);

        final response = await store.queryProductDetails({'product'});
        expect(response.error, isNull);
        expect(response.productDetails, isNotEmpty);
        expect(store.catalogRequests, 1);

        expect(
          await store.isIntroductoryOfferEligible(pomodoistMonthlyProductId),
          isTrue,
        );
        expect(store.eligibilityChecks, contains(pomodoistMonthlyProductId));

        expect(await store.latestSubscriptionTransaction(), isNull);

        final restored = await store.restorePurchases();
        expect(restored, isNotNull);
        expect(store.restoreCount, 1);
        expect(store.refreshCount, 1);

        expect(store.purchaseStream, isNotNull);
        await store.close();
      });

      test('calendar integration repository serves streams', () async {
        final repository = FakeCalendarIntegrationRepository();

        expect(await repository.watchConnection().first, isNull);
        expect(await repository.watchLinkForTask('task-1').first, isNull);
        expect(repository.watchLinkForTaskCalls, ['task-1']);
      });

      test('focus repository records the run lifecycle', () async {
        final repository = FakeFocusRepository();

        expect(await repository.watchPresets().first, isEmpty);
        expect(valueOf(await repository.createPreset(
          buildCreateFocusPresetInput(),
        )), 'preset-1');
        expect(repository.createPresetCalls, hasLength(1));

        expect(valueOf(await repository.startRun(buildStartFocusRunInput())),
            'run-1');
        expect(repository.startRunCalls, hasLength(1));

        expectOk(await repository.stopActiveRun(
          reason: StopFocusReason.stopped,
        ));
        expect(repository.stopActiveRunCalls.single.reason,
            StopFocusReason.stopped);

        expectOk(await repository.deletePreset('preset-1'));
        expect(repository.deletePresetCalls, ['preset-1']);
      });

      test('kanban repository serves the board', () async {
        final repository = FakeKanbanRepository();
        final board = buildKanbanBoard();

        expect(await repository.watchBoard().first, isNotNull);
        repository.board = board;
        expect(await repository.watchBoard().first, same(board));

        expect(valueOf(await repository.createStatus('Doing')), 'status-1');
        expect(repository.createStatusCalls.single.name, 'Doing');
        expectOk(await repository.moveTask('task-1', statusId: 'status-1'));
        expect(repository.moveTaskCalls.single.taskId, 'task-1');
      });

      test('label repository answers labels', () async {
        final repository = FakeLabelRepository();

        expect(await repository.watchLabels().first, isEmpty);
        expect(valueOf(await repository.createLabel('Errand')), 'label-1');
        expect(repository.createLabelCalls.single.name, 'Errand');
        expect(valueOf(await repository.findByName('Errand')), isNull);
        expect(repository.findByNameCalls, ['Errand']);
        expectOk(await repository.deleteLabel('label-1'));
      });

      test('project repository answers projects', () async {
        final repository = FakeProjectRepository();

        expect(await repository.watchProjects().first, isEmpty);
        expect(valueOf(await repository.createProject('Inbox')), 'created-project');
        expect(repository.created.single.name, 'Inbox');
        expect(valueOf(await repository.findByName('Inbox')), isNull);
        expectOk(await repository.moveProject('project-1', parentId: null));
        expect(repository.moved, hasLength(1));
        expectOk(
          await repository.updateProject(
            'project-1',
            buildUpdateProjectPatch(name: 'Renamed'),
          ),
        );
        expect(repository.updated.single.patch.name, 'Renamed');
        expectOk(await repository.deleteProject('project-1'));
        expect(repository.deleted, ['project-1']);
      });

      test('task repository answers tasks', () async {
        final repository = FakeTaskRepository();

        expect(await repository.watchTasks(buildTaskQuery()).first, isEmpty);
        expect(await repository.watchTask('task-1').first, isNull);
        expect(valueOf(await repository.createTask(buildCreateTaskInput())),
            'task-1');
        expect(repository.created.single.content, 'Task 1');

        expect(
          valueOf(
            await repository.duplicateTasks({'task-1'}, includeSubtasks: false),
          ),
          isEmpty,
        );
        expect(repository.duplicated.single.includeSubtasks, isFalse);

        expectOk(await repository.completeTask('task-1'));
        expect(repository.completed, ['task-1']);
        expectOk(await repository.deleteTask('task-1'));
        expect(repository.deleted, ['task-1']);
      });

      test('sync repository replays a sync result', () async {
        final repository = FakeSyncRepository();

        final result = await repository.syncNow(
          session: (userId: 'user-1', generation: 1),
          retentionCutoff: null,
        );
        expect(valueOf(result), {'task'});
        expect(repository.syncNowCalls.single.session.userId, 'user-1');
      });

      test('task decomposer serves drafts', () async {
        final decomposer = FakeTaskDecomposer();

        final drafts = await decomposer.decompose(
          'buy milk',
          now: DateTime.utc(2026),
          locale: 'en',
        );
        expect(drafts, isEmpty);
        expect(decomposer.transcripts, ['buy milk']);
        expect(decomposer.locales, ['en']);
      });

      test('voice recorder serves amplitude and transcripts', () async {
        final recorder = FakeVoiceRecorder();

        expect(await recorder.hasPermission(), isTrue);
        expect(recorder.hasPermissionCalls.single.request, isTrue);
        expect(await recorder.amplitudeDbfs.first, 0);

        await recorder.start('/tmp/recording.m4a');
        expect(await recorder.stop(), '/tmp/recording.m4a');
        await recorder.cancel();
        await recorder.dispose();
        expect(recorder.cancelCalls, hasLength(1));
      });

      test('voice capture repository serves state and commands', () async {
        final repository = FakeVoiceCaptureRepository();

        expect((await repository.watchState().first).restoring, isFalse);
        expectOk(await repository.start('en'));
        expect(repository.startCalls.single.locale, 'en');
        expectOk(await repository.stop());
        expect(valueOf(await repository.close()), isTrue);
        expectOk(await repository.restore());
        expectOk(await repository.refreshAccess(locale: 'en'));
        expect(repository.refreshAccessCalls.single.request, isFalse);
        expectOk(await repository.recoverAccess('en'));
        expectOk(await repository.useCloudTranscription('en'));
      });

      test('outbox service records enqueued commands', () async {
        final service = FakeOutboxService();

        await service.enqueue(type: 'task', payload: const {'id': 'task-1'});
        expect(service.enqueueCalls.single.type, 'task');
        expect(await service.watchPending().first, isEmpty);
        expect(service.watchPendingCalls, hasLength(1));

        service.enqueueError = StateError('boom');
        expect(
          () {
            service.enqueue(type: 'task', payload: const {});
          },
          throwsStateError,
        );

        await service.dispose();
      });

      test('quick add hint doubles answer hints', () async {
        final history = FakeQuickAddHintHistory()
          ..titles = const ['one', 'two', 'three'];

        expect(await history.countExistingUserTasks(), 0);
        expect(await history.recentTaskTitles(limit: 2), ['one', 'two']);
        expect(history.recentTaskTitlesCalls.single.limit, 2);

        final generator = FakeQuickAddHintGenerator();
        expect(
          await generator.generate(recentTaskTitles: const [], locale: 'en'),
          'Plan the day #Work @planning 09:00',
        );
        expect(generator.generateCalls.single.locale, 'en');
      });

      test('startup monitor runs and captures failures', () async {
        final monitor = FakeStartupMonitor();
        final policy = SentryRuntimePolicy.fromValues(
          environment: 'local',
          release: '1.0.0',
          sentryDsn: '',
        );

        await monitor.run(policy, () async {});
        expect(monitor.runCalls, hasLength(1));
        expect(monitor.capturedErrors, isEmpty);

        await expectLater(
          monitor.run(policy, () async => throw StateError('boom')),
          throwsStateError,
        );
        expect(monitor.capturedErrors, hasLength(1));
      });

      test('notification scheduler doubles record scheduling', () async {
        final scheduler = FakeNotificationScheduler();

        await scheduler.initialize();
        expect(await scheduler.pendingTaskStartTaskIds(), isEmpty);
        await scheduler.scheduleTaskStart(
          taskId: 'task-1',
          startAt: DateTime.utc(2026),
          title: 'Task 1',
          body: 'Starting',
        );
        await scheduler.cancelTaskStart('task-1');
        await scheduler.cancelReengagementReminder();
        expect(scheduler.cancelReengagementCount, 1);

        final reengagement = FakeReengagementNotificationScheduler();
        await reengagement.requestNotificationPermissions();
        await reengagement.scheduleReengagementReminder(
          firstAt: DateTime.utc(2026),
          copy: const NotificationCopy.english(),
        );
        expect(reengagement.permissionRequestCount, 1);
        expect(reengagement.scheduledReengagementTitle, contains('Pomo'));
        await reengagement.scheduleTaskStart(
          taskId: 'task-2',
          startAt: DateTime.utc(2026),
          title: 'Task 2',
          body: 'Starting',
        );
        await reengagement.cancelTaskStart('task-2');
        expect(reengagement.canceledTaskStarts, ['task-2']);
      });

      test('update doubles serve offers and installs', () async {
        final offer = UpdateOffer(
          tag: 'v1.0.0',
          version: UpdateVersion.parse('1.0.0'),
          notes: 'notes',
          asset: UpdateAsset(
            name: 'pomodoist.zip',
            url: Uri.parse('https://example.com/pomodoist.zip'),
            size: 1,
          ),
        );

        final source = FakeUpdateSource()..offer = offer;
        final found = await source.findUpdate(
          current: UpdateVersion.parse('0.9.0'),
          target: const UpdateTarget(UpdateOS.linux, UpdateArch.x64),
          channel: UpdateChannel.stable,
        );
        expect(found, same(offer));
        expect(source.findUpdateCalls.single.current.text, '0.9.0');
        source.dispose();
        expect(source.disposeCalls, hasLength(1));

        final installer = FakeUpdateInstaller();
        expect(await installer.acknowledgeStartup(), isNull);
        expect(installer.acknowledgeStartupCalls, hasLength(1));
        await installer.install(offer, (phase, fraction) {});
        expect(installer.installCalls, hasLength(1));
        installer.dispose();
        expect(installer.disposeCalls, hasLength(1));
      });

      test('recorded recognizer replays a transcript', () async {
        final transcript = VoiceRecognitionTranscript(text: 'hello');
        final recognizer = FakeRecordedRecognizer(transcript: transcript);

        expect(recognizer.canRetryTranscription, isFalse);
        expect(await recognizer.restorePendingRecording(), isFalse);

        recognizer.pendingRecording = true;
        expect(recognizer.canRetryTranscription, isTrue);
        expect(await recognizer.retryTranscription(), same(transcript));
        expect(recognizer.retryCalls, 1);
        expect(recognizer.pendingRecording, isFalse);

        await recognizer.cancel();
        recognizer.dispose();
        expect(recognizer.cancelCalls, 1);
      });

      test('linux shortcuts portal records registration', () async {
        final portal = FakeLinuxShortcutsPortal();

        expect(await portal.isAvailable(), isTrue);
        await portal.enable(preferredTrigger: '<Ctrl>K', onActivated: () {});
        expect(portal.enabledTrigger, '<Ctrl>K');
        await portal.disable();
        expect(portal.disableCalls, 1);
        await portal.dispose();
      });
    });

    group('fixtures', () {
      test('order keys advance past the alphabet', () {
        expect(fixtureOrderKey(0), 'a');
        expect(fixtureOrderKey(25), 'z');
        expect(fixtureOrderKey(26), 'aa');
      });

      test('task fixtures build deterministic collections', () {
        final tasks = buildTasks(3);

        expect(tasks, hasLength(3));
        expect(tasks.map((task) => task.id), ['task-1', 'task-2', 'task-3']);
        expect(tasks.map((task) => task.orderKey), ['a', 'b', 'c']);
        expect(buildTask().content, 'Task 1');
        expect(buildProjects(2), hasLength(2));
        expect(buildLabels(2), hasLength(2));
      });

      test('billing fixtures expose named states', () {
        expect(BillingFixtures.free().loading, isFalse);
        expect(BillingFixtures.free().storeAvailable, isTrue);
        expect(
          BillingFixtures.monthly().purchasedProductIds,
          {pomodoistMonthlyProductId},
        );
        expect(
          BillingFixtures.lifetime().activeStoreKitProductIds,
          {pomodoistLifetimeProductId},
        );
        expect(BillingFixtures.expired().activeProductId, isNull);
        expect(
          BillingFixtures.storeUnavailable().missingProductIds,
          billingProductIds,
        );
        expect(
          BillingFixtures.purchasePending().pendingProductId,
          pomodoistAnnualProductId,
        );
      });

      test('focus fixtures build presets and runs', () {
        expect(focusPresetPomodoro().isDefault, isTrue);
        expect(focusPresetDeepWork().name, 'Deep Work');
        expect(buildFocusRun().status, 'active');
        expect(buildFocusInterval().type, 'work');
        expect(
          buildStartFocusRunInput(presetId: defaultPresetId).presetId,
          defaultPresetId,
        );
      });

      test('planning fixtures build drafts and achievements', () {
        expect(buildDecomposedTaskDraft().quickAdd, 'Buy milk');
        expect(buildDecomposedTaskDrafts(2), hasLength(2));
        expect(
          buildAchievements(2).map((achievement) => achievement.id),
          ['achievement_1', 'achievement_2'],
        );
        expect(buildAchievement().target, 1);
      });
    });
  });
}
