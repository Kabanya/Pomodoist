import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_account/app_account.dart';
import 'package:app_voice/app_voice.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/onboarding/onboarding_gate.dart';
import 'package:pomodoist/features/planning/data/task_decomposer.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/quick_add_bar.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/task_list_view.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final emptySuggestionOverrides = [
    projectsProvider.overrideWith((ref) => Stream.value(const <ProjectItem>[])),
    labelsProvider.overrideWith((ref) => Stream.value(const <LabelItem>[])),
    quickAddHintTextProvider.overrideWithValue(null),
  ];
  final proVoiceOverrides = [
    ...emptySuggestionOverrides,
    billingAccountEntitlementProvider.overrideWithValue(true),
  ];

  test(
    'account bootstrap changes do not recreate the voice controller',
    () async {
      const recordChannel = MethodChannel('com.llfbandit.record/messages');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(recordChannel, (_) async => null);
      final container = ProviderContainer(
        overrides: [accountClientProvider.overrideWithValue(null)],
      );
      try {
        final original = container.read(voiceRecognitionControllerProvider);
        final account = AccountClient.fromSupabaseClient(
          SupabaseClient('http://localhost', 'test-key'),
        );

        container.updateOverrides([
          accountClientProvider.overrideWithValue(account),
        ]);

        expect(
          container.read(voiceRecognitionControllerProvider),
          same(original),
        );
      } finally {
        container.dispose();
        await pumpEventQueue();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(recordChannel, null);
      }
    },
  );

  testWidgets('busy iOS microphone shows an actionable localized error', (
    tester,
  ) async {
    final controller = VoiceRecognitionController(
      recordedRecognizer: _FakeRecordedRecognizer(
        transcript: const VoiceRecognitionTranscript(text: ''),
        startError: PlatformException(
          code: 'record',
          message: 'Failed to start recording',
          details: 'setActive: Session activation failed',
        ),
      ),
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Голосовое добавление'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Записать'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Микрофон сейчас недоступен. Завершите активный звонок или '
        'голосовой чат и повторите попытку.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
  });

  test('logged-out Pro sends StoreKit proof for analysis', () async {
    final httpClient = _FunctionHttpClient();

    final account = AccountClient.fromSupabaseClient(
      SupabaseClient(
        'http://localhost:54321',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: httpClient,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        billingStoreProvider.overrideWithValue(
          BillingStore(
            transactionLoader: () async => const [
              BillingTransactionProof(
                productId: pomodoistLifetimeProductId,
                jws: 'signed-pomodoist',
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final tasks = await container
        .read(taskDecomposerProvider)
        .decompose(
          'buy milk',
          now: DateTime.utc(2026, 7, 21, 12),
          locale: 'en-US',
        );

    expect(tasks.single.quickAdd, 'Buy milk');
    expect(httpClient.body, {
      'command': {
        'type': 'task.decomposeTranscript',
        'transcript': 'buy milk',
        'locale': 'en-US',
        'currentLocalTime': isA<String>(),
        'smart': false,
      },
      'storeTransactions': ['signed-pomodoist'],
    });
  });

  testWidgets('quick add suggestions insert project and label tokens', (
    tester,
  ) async {
    final createdAt = DateTime.utc(2026);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith(
            (ref) => Stream.value([
              ProjectItem(
                id: 'product',
                userId: localUserId,
                name: 'Product Launch',
                orderKey: 'a',
                createdAt: createdAt,
                updatedAt: createdAt,
              ),
              ProjectItem(
                id: 'archived',
                userId: localUserId,
                name: 'Archived Product',
                orderKey: 'b',
                isArchived: true,
                createdAt: createdAt,
                updatedAt: createdAt,
              ),
            ]),
          ),
          labelsProvider.overrideWith(
            (ref) => Stream.value([
              LabelItem(
                id: 'deep-work',
                userId: localUserId,
                name: 'Deep Work',
                orderKey: 'a',
                createdAt: createdAt,
                updatedAt: createdAt,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, '#P');
    await tester.pump();

    expect(find.text('Product Launch'), findsOneWidget);
    expect(find.text('Archived Product'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      tester.widget<TextField>(field).controller!.text,
      '#"Product Launch" ',
    );

    await tester.enterText(field, '#"Product Launch" @D');
    await tester.pump();

    expect(find.text('Deep Work'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      tester.widget<TextField>(field).controller!.text,
      '#"Product Launch" @"Deep Work" ',
    );
  });

  testWidgets('quick add bar forwards default date and Kanban status', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...emptySuggestionOverrides,
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QuickAddBar(
              defaultDate: DateTime(2026, 5, 5),
              kanbanStatusId: kanbanStatusTodoId,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'Typed contextual task 08:45',
    );
    await tester.tap(find.byTooltip('Add'));

    var rows = await db.select(db.tasks).get();
    for (
      var attempt = 0;
      attempt < 20 &&
          !rows.any((task) => task.content == 'Typed contextual task');
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
      rows = await db.select(db.tasks).get();
    }
    final created = rows.singleWhere(
      (task) => task.content == 'Typed contextual task',
    );
    final schedule = TaskSchedule.fromJsonString(created.dueJson);

    expect(schedule!.start!.toLocal(), DateTime(2026, 5, 5, 8, 45));
    final assignment =
        await (db.select(db.taskLabels)..where(
              (row) =>
                  row.taskId.equals(created.id) &
                  row.kind.equals(labelKindKanbanStatus),
            ))
            .getSingle();
    expect(assignment.labelId, kanbanStatusTodoId);
  });

  testWidgets('quick add confirms success and keeps input focused', (
    tester,
  ) async {
    final creation = Completer<String>();
    final service = _QuickAddMotionService(() => creation.future);
    final createdIds = <String>[];
    await tester.pumpWidget(
      _quickAddMotionApp(service, onTaskCreated: createdIds.addAll),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, 'Animated task');
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    expect(find.byKey(const Key('quick-add-submit-progress')), findsOneWidget);

    creation.complete('task-1');
    for (var attempt = 0; attempt < 20 && createdIds.isEmpty; attempt++) {
      await tester.pump();
    }
    expect(createdIds, hasLength(1));
    expect(find.byKey(const Key('quick-add-submit-success')), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('quick-add-submit-progress')), findsNothing);
    expect(find.byKey(const Key('quick-add-submit-success')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 799));
    expect(find.byKey(const Key('quick-add-submit-success')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-submit-idle')), findsNothing);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-add-submit-idle')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-submit-success')), findsNothing);
  });

  testWidgets('a repeated submit replaces pending success feedback', (
    tester,
  ) async {
    final creations = [Completer<String>(), Completer<String>()];
    var nextCreation = 0;
    final service = _QuickAddMotionService(
      () => creations[nextCreation++].future,
    );
    final createdIds = <String>[];
    await tester.pumpWidget(
      _quickAddMotionApp(service, onTaskCreated: createdIds.addAll),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, 'First task');
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    creations[0].complete('task-1');
    for (var attempt = 0; attempt < 20 && createdIds.isEmpty; attempt++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('quick-add-submit-success')), findsOneWidget);

    await tester.enterText(field, 'Second task');
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    expect(find.byKey(const Key('quick-add-submit-progress')), findsOneWidget);
    creations[1].complete('task-2');
    for (var attempt = 0; attempt < 20 && createdIds.length < 2; attempt++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 919));
    expect(find.byKey(const Key('quick-add-submit-success')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-submit-idle')), findsNothing);
    await tester.pump(const Duration(milliseconds: 121));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-add-submit-idle')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-submit-success')), findsNothing);
  });

  testWidgets('quick add failure retains input without success feedback', (
    tester,
  ) async {
    final service = _QuickAddMotionService(
      () => Future<String>.error(StateError('create failed')),
    );
    await tester.pumpWidget(_quickAddMotionApp(service));

    final field = find.byType(TextField);
    await tester.enterText(field, 'Keep this task');
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field).controller!.text, 'Keep this task');
    expect(find.byKey(const Key('quick-add-submit-success')), findsNothing);
    expect(find.byKey(const Key('quick-add-submit-idle')), findsOneWidget);
    expect(find.text('Could not create the task. Try again.'), findsOneWidget);
  });

  testWidgets('Reduce Motion skips transient quick add success feedback', (
    tester,
  ) async {
    final service = _QuickAddMotionService(() async => 'task-1');
    final createdIds = <String>[];
    await tester.pumpWidget(
      _quickAddMotionApp(
        service,
        disableAnimations: true,
        onTaskCreated: createdIds.addAll,
      ),
    );

    await tester.enterText(find.byType(TextField), 'Reduced task');
    await tester.tap(find.byTooltip('Add'));
    for (var attempt = 0; attempt < 20 && createdIds.isEmpty; attempt++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(createdIds, hasLength(1));
    expect(find.byKey(const Key('quick-add-submit-idle')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-submit-success')), findsNothing);
    expect(
      tester
          .widget<AnimatedSwitcher>(
            find.descendant(
              of: find.byKey(const Key('quick-add-motion-submit')),
              matching: find.byType(AnimatedSwitcher),
            ),
          )
          .duration,
      Duration.zero,
    );
  });

  testWidgets('quick add bar uses project context unless # overrides it', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...emptySuggestionOverrides,
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar(projectId: 'project-context')),
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, 'Context task');
    await tester.tap(find.byTooltip('Add'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(field, 'Explicit task #Explicit');
    await tester.tap(find.byTooltip('Add'));
    await tester.pump(const Duration(milliseconds: 300));

    final rows = await db.select(db.tasks).get();
    final contextTask = rows.singleWhere(
      (task) => task.content == 'Context task',
    );
    final explicitTask = rows.singleWhere(
      (task) => task.content == 'Explicit task',
    );
    final explicitProject = (await db.select(db.projects).get()).singleWhere(
      (project) => project.name == 'Explicit',
    );

    expect(contextTask.projectId, 'project-context');
    expect(explicitTask.projectId, explicitProject.id);
  });

  testWidgets('voice drafts can be edited and accepted as tasks', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();

    final recordedRecognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(
        text: 'купить кофе и написать отчет завтра утром',
      ),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recordedRecognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          appDatabaseProvider.overrideWithValue(db),
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(
            const _FakeTaskDecomposer([
              DecomposedTaskDraft(quickAdd: 'Купить кофе today 09:00 30m'),
              DecomposedTaskDraft(
                quickAdd: 'Написать отчет tomorrow 10:00 1h',
                description: 'Собрать цифры по кварталу',
              ),
            ]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();

    expect(find.text('Text'), findsNothing);
    expect(find.text('Tap record and dictate tasks.'), findsNothing);
    expect(find.text('Record'), findsWidgets);
    expect(find.text('Analyze'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(
      tester.widget<Switch>(find.byKey(const Key('voice-smart-mode'))).value,
      isFalse,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();

    expect(recordedRecognizer.startCalls, 1);
    expect(find.text('5:00'), findsOneWidget);
    expect(
      find.text('купить кофе и написать отчет завтра утром'),
      findsNothing,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Stop'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Record'))
          .onPressed,
      isNull,
    );

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('4:59'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(find.text('Купить кофе today 09:00 30m'), findsOneWidget);
    expect(find.text('Написать отчет tomorrow 10:00 1h'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Task 1',
      ),
      'Написать отчет tomorrow 10:00 1h p1',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 1'));
    await tester.pump(const Duration(milliseconds: 300));

    final created = await (db.select(
      db.tasks,
    )..where((task) => task.content.equals('Написать отчет'))).getSingle();
    final schedule = TaskSchedule.fromJsonString(created.dueJson);

    expect(created.description, 'Собрать цифры по кварталу');
    expect(created.priority, 1);
    expect(schedule?.isTimed, isTrue);
    expect(schedule?.start?.toLocal().hour, 10);
    expect(schedule?.duration, const Duration(hours: 1));
  });

  testWidgets('voice records for five minutes and stops exactly once', (
    tester,
  ) async {
    final recognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(
            const _FakeTaskDecomposer([
              DecomposedTaskDraft(quickAdd: 'Buy milk'),
            ]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();
    expect(find.text('5:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 59));
    expect(recognizer.stopCalls, 0);
    expect(find.text('4:01'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-collapse')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 240));
    expect(recognizer.stopCalls, 0);
    await tester.tap(find.byKey(const Key('voice-expand')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('0:01'), findsOneWidget);
    final stop = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Stop'))
        .onPressed!;
    await tester.pump(const Duration(seconds: 1));
    stop(); // A queued manual stop must not transcribe a second time.
    await tester.pumpAndSettle();
    expect(recognizer.stopCalls, 1);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.byKey(const Key('voice-recording-countdown')), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Again'));
    // A completed subscription's cancel future may belong to the real zone.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('5:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Stop'));
    await tester.pumpAndSettle();
    expect(recognizer.stopCalls, 2);
    await tester.pump(const Duration(minutes: 5));
    expect(recognizer.stopCalls, 2);

    await tester.tap(find.widgetWithText(FilledButton, 'Again'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 5));
    expect(recognizer.cancelCalls, 1);
    expect(recognizer.stopCalls, 2);
  });

  testWidgets('voice recording survives collapse drag and reopen', (
    tester,
  ) async {
    final recognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();

    expect(find.byKey(const Key('voice-collapse')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-collapse')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final panel = find.byKey(const Key('voice-mini-panel'));
    expect(tester.getSize(panel), const Size(168, 64));
    expect(find.byKey(const Key('voice-mini-recording')), findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.byType(Text)),
      findsNothing,
    );
    final originalPosition = tester.getTopLeft(panel);
    await tester.drag(
      find.byKey(const Key('voice-drag-handle')),
      const Offset(-600, -500),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(panel), isNot(originalPosition));
    expect(recognizer.startCalls, 1);
    expect(recognizer.stopCalls, 0);
    expect(recognizer.cancelCalls, 0);

    await tester.tap(find.byKey(const Key('voice-expand')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(panel, findsNothing);
    expect(find.byKey(const Key('voice-recording-countdown')), findsOneWidget);
    expect(find.byKey(const Key('voice-amplitude-bars')), findsOneWidget);
    expect(recognizer.startCalls, 1);
    expect(recognizer.cancelCalls, 0);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(recognizer.cancelCalls, 1);
  });

  testWidgets('collapsed voice analysis keeps results and edited drafts', (
    tester,
  ) async {
    final recognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk and coffee'),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    final decomposer = _WaitingTaskDecomposer();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(decomposer),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('voice-collapse')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('voice-mini-stop')));
    await tester.pump();

    expect(find.byKey(const Key('voice-mini-processing')), findsOneWidget);
    expect(find.byKey(const Key('voice-mini-recording')), findsNothing);
    expect(decomposer.transcripts, ['buy milk and coffee']);
    expect(recognizer.stopCalls, 1);
    expect(recognizer.cancelCalls, 0);
    decomposer.complete(const [
      DecomposedTaskDraft(quickAdd: 'Buy milk'),
      DecomposedTaskDraft(quickAdd: 'Buy coffee'),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-mini-ready')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('voice-mini-panel')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('voice-expand')));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Buy coffee'), findsOneWidget);
    final firstDraft = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Task 1',
    );
    await tester.enterText(firstDraft, 'Buy oat milk p1');
    await tester.tap(find.byKey(const Key('voice-collapse')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-expand')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(firstDraft).controller!.text,
      'Buy oat milk p1',
    );
    expect(find.text('Buy coffee'), findsOneWidget);
    expect(find.text('Add 2'), findsOneWidget);
    expect(recognizer.startCalls, 1);
    expect(decomposer.transcripts, hasLength(1));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('voice tasks retain source defaults after navigating away', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final recognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    final decomposer = _WaitingTaskDecomposer();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          appDatabaseProvider.overrideWithValue(db),
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(decomposer),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () =>
                      navigator.currentState!.pushReplacement<void, void>(
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            body: QuickAddBar(
                              defaultPriority: 4,
                              defaultDate: DateTime(2026, 10, 10),
                              projectId: 'destination-project',
                            ),
                          ),
                        ),
                      ),
                  child: const Text('Leave source'),
                ),
                QuickAddBar(
                  key: const Key('voice-source-bar'),
                  defaultPriority: 2,
                  defaultDate: DateTime(2026, 9, 9),
                  projectId: 'source-project',
                  kanbanStatusId: kanbanStatusTodoId,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('voice-collapse')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('voice-mini-stop')));
    await tester.pump();
    expect(find.byKey(const Key('voice-mini-processing')), findsOneWidget);

    await tester.tap(find.text('Leave source'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('voice-source-bar'), skipOffstage: false),
      findsNothing,
    );
    expect(find.byKey(const Key('voice-mini-processing')), findsOneWidget);
    decomposer.complete(const [
      DecomposedTaskDraft(quickAdd: 'Buy milk', description: 'Oat milk'),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-expand')));
    await tester.pumpAndSettle();
    final add = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add 1'))
        .onPressed!;
    await tester.tap(find.text('Add 1'));
    add(); // A queued second tap must not create a duplicate task.
    await tester.pumpAndSettle();

    final created = await (db.select(
      db.tasks,
    )..where((task) => task.content.equals('Buy milk'))).getSingle();
    expect(created.description, 'Oat milk');
    expect(created.priority, 2);
    expect(created.projectId, 'source-project');
    expect(
      TaskSchedule.fromJsonString(created.dueJson)?.displayDate,
      DateTime(2026, 9, 9),
    );
    final assignment =
        await (db.select(db.taskLabels)..where(
              (row) =>
                  row.taskId.equals(created.id) &
                  row.kind.equals(labelKindKanbanStatus),
            ))
            .getSingle();
    expect(assignment.labelId, kanbanStatusTodoId);
    expect(find.byKey(const Key('voice-mini-panel')), findsNothing);
    expect(find.byKey(const Key('voice-collapse')), findsNothing);
    expect(recognizer.startCalls, 1);
    expect(recognizer.stopCalls, 1);
    expect(recognizer.cancelCalls, 0);
  });

  testWidgets('voice controls remain reachable in landscape with a keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(740, 340);
    tester.view.viewInsets = const FakeViewPadding(bottom: 120);
    addTearDown(tester.view.reset);
    final recognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final record = find.widgetWithText(FilledButton, 'Record');
    await tester.ensureVisible(record);
    await tester.pumpAndSettle();
    expect(tester.getRect(record).bottom, lessThanOrEqualTo(220));
    await tester.tap(record);
    await tester.pump();
    expect(recognizer.startCalls, 1);
    await tester.ensureVisible(find.byTooltip('Close'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(recognizer.cancelCalls, 1);
  });

  testWidgets(
    'voice mini panel snaps inside safe keyboard and resized bounds',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final recognizer = _FakeRecordedRecognizer(
        transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
      );
      final controller = VoiceRecognitionController(
        recordedRecognizer: recognizer,
        platformSupport: const VoicePlatformSupport(
          supportsRecordedSystem: true,
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...proVoiceOverrides,
            applePurchasesSupportedProvider.overrideWithValue(false),
            voiceRecognitionControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: QuickAddBar()),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Voice quick add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('voice-collapse')));
      await tester.pump();

      final panel = find.byKey(const Key('voice-mini-panel'));
      final handle = find.byKey(const Key('voice-drag-handle'));
      for (final target in const [
        Offset(80, 80),
        Offset(720, 80),
        Offset(80, 520),
        Offset(720, 520),
      ]) {
        await tester.drag(handle, target - tester.getCenter(handle));
        await tester.pump();
        final rect = tester.getRect(panel);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(24));
        expect(rect.right, lessThanOrEqualTo(800));
        expect(rect.bottom, lessThanOrEqualTo(580));
        expect(
          target.dx < 400 ? rect.left : 800 - rect.right,
          inInclusiveRange(0, 24),
        );
        expect(
          target.dy < 300 ? rect.top - 24 : 580 - rect.bottom,
          inInclusiveRange(0, 24),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.getRect(panel),
          rect,
          reason: 'Reduce Motion snaps immediately',
        );
      }

      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pump();
      expect(tester.getRect(panel).bottom, lessThanOrEqualTo(380));
      tester.view.physicalSize = const Size(360, 520);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pump();
      final resized = tester.getRect(panel);
      expect(resized.left, greaterThanOrEqualTo(0));
      expect(resized.top, greaterThanOrEqualTo(24));
      expect(resized.right, inInclusiveRange(336, 360));
      expect(resized.bottom, inInclusiveRange(316, 340));
      expect(recognizer.cancelCalls, 0);
      expect(recognizer.stopCalls, 0);

      tester.view.viewInsets = const FakeViewPadding();
      tester.view.physicalSize = const Size(800, 600);
      await tester.pump();
      await tester.tap(find.byKey(const Key('voice-expand')));
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(recognizer.cancelCalls, 1);
    },
  );

  testWidgets(
    'collapsed voice analysis error can retry without recording again',
    (tester) async {
      final recognizer = _FakeRecordedRecognizer(
        transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
      );
      final controller = VoiceRecognitionController(
        recordedRecognizer: recognizer,
        platformSupport: const VoicePlatformSupport(
          supportsRecordedSystem: true,
        ),
      );
      final decomposer = _FlakyTaskDecomposer();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...proVoiceOverrides,
            applePurchasesSupportedProvider.overrideWithValue(false),
            voiceRecognitionControllerProvider.overrideWithValue(controller),
            taskDecomposerProvider.overrideWithValue(decomposer),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: QuickAddBar()),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Voice quick add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('voice-collapse')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('voice-mini-stop')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voice-mini-error')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('voice-mini-stop')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('voice-expand')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry analysis'));
      await tester.pumpAndSettle();
      expect(find.text('Buy milk tomorrow'), findsOneWidget);
      expect(decomposer.calls, 2);
      expect(recognizer.startCalls, 1);
      expect(recognizer.stopCalls, 1);
      expect(recognizer.cancelCalls, 0);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('closing the voice sheet cancels the active recording', (
    tester,
  ) async {
    final recordedRecognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recordedRecognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(recordedRecognizer.cancelCalls, 1);
  });

  testWidgets('voice recording bars react to microphone amplitude', (
    tester,
  ) async {
    final amplitudes = StreamController<double>.broadcast();
    addTearDown(amplitudes.close);
    final recordedRecognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
      amplitudeDbfs: amplitudes.stream,
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recordedRecognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    final decomposer = _WaitingTaskDecomposer();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(decomposer),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-amplitude-bars')), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();
    expect(find.byKey(const Key('voice-amplitude-bars')), findsOneWidget);

    final centerBar = find.byKey(const Key('voice-amplitude-bar-2'));
    final before = tester
        .widget<AnimatedContainer>(centerBar)
        .constraints!
        .maxHeight;
    amplitudes.add(0);
    await tester.pump(const Duration(milliseconds: 120));
    final after = tester
        .widget<AnimatedContainer>(centerBar)
        .constraints!
        .maxHeight;
    expect(after, 32);
    expect(after, greaterThan(before));

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.byKey(const Key('voice-amplitude-bars')), findsNothing);

    decomposer.complete(const [DecomposedTaskDraft(quickAdd: 'Buy milk')]);
    await tester.pumpAndSettle();
  });

  testWidgets('voice recording bars respect reduced motion', (tester) async {
    final amplitudes = StreamController<double>.broadcast();
    addTearDown(amplitudes.close);
    final recordedRecognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
      amplitudeDbfs: amplitudes.stream,
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recordedRecognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();

    final centerBar = find.byKey(const Key('voice-amplitude-bar-2'));
    amplitudes.add(-50);
    await tester.pump();
    final quiet = tester
        .widget<AnimatedContainer>(centerBar)
        .constraints!
        .maxHeight;
    amplitudes.add(-5);
    await tester.pump();
    final loud = tester
        .widget<AnimatedContainer>(centerBar)
        .constraints!
        .maxHeight;
    expect(loud, quiet);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('voice quick add uses default priority', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();

    final recordedRecognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recordedRecognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          appDatabaseProvider.overrideWithValue(db),
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(
            const _FakeTaskDecomposer([
              DecomposedTaskDraft(quickAdd: 'Buy milk'),
            ]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar(defaultPriority: 2)),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 1'));
    await tester.pump(const Duration(milliseconds: 300));

    final created = await (db.select(
      db.tasks,
    )..where((task) => task.content.equals('Buy milk'))).getSingle();
    expect(created.priority, 2);
  });

  testWidgets('Today task list defaults quick add to its date', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final today = DateTime(2026, 5, 5);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...emptySuggestionOverrides,
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TaskListView(
              title: 'Today',
              query: TaskQuery(kind: TaskQueryKind.today, now: today),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    final created = await (db.select(
      db.tasks,
    )..where((task) => task.content.equals('Buy milk'))).getSingle();
    expect(TaskSchedule.fromJsonString(created.dueJson)?.displayDate, today);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'voice quick add uses default date unless a nested draft is explicit',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();

      final recordedRecognizer = _FakeRecordedRecognizer(
        transcript: const VoiceRecognitionTranscript(text: 'plan launch'),
      );
      final controller = VoiceRecognitionController(
        recordedRecognizer: recordedRecognizer,
        platformSupport: const VoicePlatformSupport(
          supportsRecordedSystem: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...proVoiceOverrides,
            appDatabaseProvider.overrideWithValue(db),
            applePurchasesSupportedProvider.overrideWithValue(false),
            voiceRecognitionControllerProvider.overrideWithValue(controller),
            taskDecomposerProvider.overrideWithValue(
              const _FakeTaskDecomposer([
                DecomposedTaskDraft(
                  quickAdd: 'Plan launch',
                  subtasks: [
                    DecomposedTaskDraft(
                      quickAdd: 'Draft brief 09:00',
                      subtasks: [
                        DecomposedTaskDraft(
                          quickAdd: 'Review launch 2026-05-07 10:00',
                        ),
                      ],
                    ),
                  ],
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: QuickAddBar(defaultDate: DateTime(2026, 5, 5)),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Voice quick add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 3'));

      var rows = await db.select(db.tasks).get();
      for (
        var attempt = 0;
        attempt < 20 && !rows.any((task) => task.content == 'Review launch');
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
        rows = await db.select(db.tasks).get();
      }
      final root = rows.singleWhere((task) => task.content == 'Plan launch');
      final timed = rows.singleWhere((task) => task.content == 'Draft brief');
      final explicit = rows.singleWhere(
        (task) => task.content == 'Review launch',
      );
      final rootSchedule = TaskSchedule.fromJsonString(root.dueJson);
      final timedSchedule = TaskSchedule.fromJsonString(timed.dueJson);
      final explicitSchedule = TaskSchedule.fromJsonString(explicit.dueJson);

      expect(rootSchedule!.isAllDay, isTrue);
      expect(rootSchedule.displayDate, DateTime(2026, 5, 5));
      expect(timedSchedule!.start!.toLocal(), DateTime(2026, 5, 5, 9));
      expect(explicitSchedule!.start!.toLocal(), DateTime(2026, 5, 7, 10));
    },
  );

  testWidgets('voice quick add opens paywall without Pro', (tester) async {
    final startedAt = DateTime.utc(2026, 1, 1, 10);
    SharedPreferences.setMockInitialValues({
      launchOfferStartedAtPreferenceKey: startedAt.toIso8601String(),
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...emptySuggestionOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          clockProvider.overrideWithValue(FixedClock(startedAt)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('billing-paywall')), findsOneWidget);
    expect(find.byKey(const Key('billing-paywall-close')), findsOneWidget);
    expect(find.text('Voice add'), findsNothing);
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual.launch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.launch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('billing-paywall-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('billing-paywall')), findsNothing);
  });

  testWidgets('voice paywall hides Lifetime promo outside the weekly window', (
    tester,
  ) async {
    final startedAt = DateTime.utc(2026, 1, 1, 10);
    SharedPreferences.setMockInitialValues({
      launchOfferStartedAtPreferenceKey: startedAt.toIso8601String(),
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...emptySuggestionOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          clockProvider.overrideWithValue(
            FixedClock(startedAt.add(const Duration(hours: 25))),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual.launch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.launch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime')),
      findsOneWidget,
    );
  });

  testWidgets('voice Smart mode is restored and sent to decomposition', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'voice.smartMode': true});
    final recordedRecognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
    );
    final decomposer = _RecordingSmartTaskDecomposer();
    final controller = VoiceRecognitionController(
      recordedRecognizer: recordedRecognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(decomposer),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Switch>(find.byKey(const Key('voice-smart-mode'))).value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('voice-smart-mode')));
    await tester.pump();
    expect(
      (await SharedPreferences.getInstance()).getBool('voice.smartMode'),
      isFalse,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(decomposer.smartModes, [false]);
  });

  testWidgets('Retry analysis does not record the transcript again', (
    tester,
  ) async {
    final recordedRecognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
    );
    final decomposer = _FlakyTaskDecomposer();
    final controller = VoiceRecognitionController(
      recordedRecognizer: recordedRecognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(decomposer),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(find.text('Retry analysis'), findsOneWidget);
    expect(find.text('temporary failure'), findsOneWidget);
    expect(decomposer.calls, 1);
    expect(recordedRecognizer.stopCalls, 1);

    await tester.tap(find.text('Retry analysis'));
    await tester.pumpAndSettle();

    expect(decomposer.calls, 2);
    expect(recordedRecognizer.stopCalls, 1);
    expect(find.text('Buy milk tomorrow'), findsOneWidget);
  });

  testWidgets('voice sheet visualizes the transcript while analysis runs', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();

    final recordedRecognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(
        text: 'Купить, milk tomorrow!',
      ),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recordedRecognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    final decomposer = _WaitingTaskDecomposer();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          appDatabaseProvider.overrideWithValue(db),
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(decomposer),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();

    expect(
      find.byKey(const Key('voice-transcript-visualization')),
      findsNothing,
    );

    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(decomposer.transcripts, ['Купить, milk tomorrow!']);
    expect(
      find.byKey(const Key('voice-transcript-visualization')),
      findsOneWidget,
    );
    expect(find.text('Купить,'), findsOneWidget);
    expect(find.text('milk'), findsOneWidget);
    expect(find.text('tomorrow!'), findsOneWidget);
    final transcriptSemantics = tester.widget<Semantics>(
      find.byKey(const Key('voice-transcript-visualization')),
    );
    expect(transcriptSemantics.properties.label, 'Купить, milk tomorrow!');
    expect(
      find.text('Pomodoist is splitting speech into tasks'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('voice-analysis-status')), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsWidgets);
    expect(find.textContaining('DeepSeek'), findsNothing);

    await tester.pump(const Duration(milliseconds: 180));
    final firstWord = tester.widget<Opacity>(
      find.byKey(const Key('voice-transcript-word-0')),
    );
    final lastWord = tester.widget<Opacity>(
      find.byKey(const Key('voice-transcript-word-2')),
    );
    expect(firstWord.opacity, greaterThan(lastWord.opacity));

    final initialProgress = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value;
    expect(initialProgress, isNotNull);

    await tester.pump(const Duration(seconds: 1));

    final laterProgress = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value;
    expect(laterProgress, greaterThan(initialProgress!));

    await tester.pump(const Duration(milliseconds: 320));
    final middleWord = find.descendant(
      of: find.byKey(const Key('voice-transcript-word-1')),
      matching: find.byType(Text),
    );
    final firstColor = tester.widget<Text>(middleWord).style!.color;
    await tester.pump(const Duration(milliseconds: 650));
    final laterColor = tester.widget<Text>(middleWord).style!.color;
    expect(laterColor, isNot(firstColor));

    decomposer.complete(const [DecomposedTaskDraft(quickAdd: 'Buy coffee')]);
    await tester.pumpAndSettle();
  });

  testWidgets('voice transcript respects reduced motion', (tester) async {
    final recordedRecognizer = _FakeRecordedRecognizer(
      transcript: const VoiceRecognitionTranscript(text: 'Buy milk, please'),
    );
    final controller = VoiceRecognitionController(
      recordedRecognizer: recordedRecognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    final decomposer = _WaitingTaskDecomposer();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...proVoiceOverrides,
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(controller),
          taskDecomposerProvider.overrideWithValue(decomposer),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Voice quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();

    for (var index = 0; index < 3; index += 1) {
      expect(
        tester
            .widget<Opacity>(find.byKey(Key('voice-transcript-word-$index')))
            .opacity,
        1,
      );
    }
    final middleWord = find.descendant(
      of: find.byKey(const Key('voice-transcript-word-1')),
      matching: find.byType(Text),
    );
    final initialColor = tester.widget<Text>(middleWord).style!.color;
    await tester.pump(const Duration(milliseconds: 650));
    expect(tester.widget<Text>(middleWord).style!.color, initialColor);

    decomposer.complete(const [DecomposedTaskDraft(quickAdd: 'Buy milk')]);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'voice subtasks inherit nesting, project context, and Kanban status',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();

      final recordedRecognizer = _FakeRecordedRecognizer(
        transcript: const VoiceRecognitionTranscript(
          text: 'запустить проект с подзадачами',
        ),
      );
      final controller = VoiceRecognitionController(
        recordedRecognizer: recordedRecognizer,
        platformSupport: const VoicePlatformSupport(
          supportsRecordedSystem: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...proVoiceOverrides,
            appDatabaseProvider.overrideWithValue(db),
            applePurchasesSupportedProvider.overrideWithValue(false),
            voiceRecognitionControllerProvider.overrideWithValue(controller),
            taskDecomposerProvider.overrideWithValue(
              const _FakeTaskDecomposer([
                DecomposedTaskDraft(
                  quickAdd: 'Запустить проект',
                  subtasks: [
                    DecomposedTaskDraft(quickAdd: 'Написать бриф tomorrow'),
                    DecomposedTaskDraft(
                      quickAdd: 'Согласовать бюджет p1',
                      subtasks: [
                        DecomposedTaskDraft(
                          quickAdd: 'Собрать вводные @finance',
                        ),
                      ],
                    ),
                  ],
                ),
              ]),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: QuickAddBar(
                projectId: 'project-context',
                kanbanStatusId: kanbanStatusTodoId,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Voice quick add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(find.text('Запустить проект'), findsOneWidget);
      expect(find.text('Написать бриф tomorrow'), findsOneWidget);
      expect(find.text('Согласовать бюджет p1'), findsOneWidget);
      expect(find.text('Собрать вводные @finance'), findsOneWidget);

      await tester.tap(find.text('Add 4'));
      var rows = await db.select(db.tasks).get();
      for (
        var attempt = 0;
        attempt < 20 && !rows.any((task) => task.content == 'Собрать вводные');
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
        rows = await db.select(db.tasks).get();
      }
      final contents = rows.map((task) => task.content).toList();
      expect(
        contents,
        containsAll([
          'Запустить проект',
          'Написать бриф',
          'Согласовать бюджет',
          'Собрать вводные',
        ]),
      );

      final parent = rows.singleWhere(
        (task) => task.content == 'Запустить проект',
      );
      final brief = rows.singleWhere((task) => task.content == 'Написать бриф');
      final budget = rows.singleWhere(
        (task) => task.content == 'Согласовать бюджет',
      );
      final inputs = rows.singleWhere(
        (task) => task.content == 'Собрать вводные',
      );

      expect(parent.projectId, 'project-context');
      expect(brief.parentId, parent.id);
      expect(brief.projectId, parent.projectId);
      expect(budget.parentId, parent.id);
      expect(budget.priority, 1);
      expect(inputs.parentId, budget.id);
      expect(inputs.projectId, budget.projectId);
      final assignments =
          await (db.select(db.taskLabels)..where(
                (row) =>
                    row.taskId.isIn(rows.map((row) => row.id)) &
                    row.kind.equals(labelKindKanbanStatus),
              ))
              .get();
      expect(assignments, hasLength(rows.length));
      expect(
        assignments.map((row) => row.labelId),
        everyElement(kanbanStatusTodoId),
      );
    },
  );

  final captureDirectory = Platform.environment['VOICE_CAPTURE_DIR'];
  if (captureDirectory != null) {
    for (final viewport in const {
      'desktop': Size(1440, 1024),
      'mobile': Size(390, 844),
    }.entries) {
      for (final brightness in Brightness.values) {
        testWidgets('capture voice ${viewport.key} ${brightness.name}', (
          tester,
        ) async {
          final originalDisableShadows = debugDisableShadows;
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = originalDisableShadows);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport.value;
          addTearDown(tester.view.reset);
          await tester.runAsync(() async {
            final regular = await File(
              '.fvm/flutter_sdk/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
            ).readAsBytes();
            await (FontLoader(
              'Roboto',
            )..addFont(Future.value(ByteData.sublistView(regular)))).load();
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
          });
          final db = AppDatabase(NativeDatabase.memory());
          addTearDown(db.close);
          await db.ensureSeedData();
          final controller = VoiceRecognitionController(
            recordedRecognizer: _FakeRecordedRecognizer(
              transcript: const VoiceRecognitionTranscript(text: 'buy milk'),
              amplitudeDbfs: Stream.value(-12),
            ),
            platformSupport: const VoicePlatformSupport(
              supportsRecordedSystem: true,
            ),
          );
          addTearDown(controller.dispose);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: ProviderScope(
                overrides: [
                  ...proVoiceOverrides,
                  appDatabaseProvider.overrideWithValue(db),
                  applePurchasesSupportedProvider.overrideWithValue(false),
                  voiceRecognitionControllerProvider.overrideWithValue(
                    controller,
                  ),
                ],
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: brightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Scaffold(
                    body: TaskListView(
                      title: 'Today',
                      query: TaskQuery(
                        kind: TaskQueryKind.today,
                        now: DateTime(2026, 9, 5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          Future<void> capture(String name) => tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            await Directory(captureDirectory).create(recursive: true);
            await File(
              '$captureDirectory/$name.png',
            ).writeAsBytes(data!.buffer.asUint8List());
          });

          await tester.tap(find.byTooltip('Voice quick add'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Record'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          if (viewport.key == 'mobile' && brightness == Brightness.light) {
            await capture('mobile-light-expanded');
          }
          await tester.tap(find.byKey(const Key('voice-collapse')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            tester.getSize(find.byKey(const Key('voice-mini-panel'))),
            const Size(168, 64),
          );
          await capture('${viewport.key}-${brightness.name}-collapsed');
          await tester.tap(find.byKey(const Key('voice-expand')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          debugDisableShadows = originalDisableShadows;
        });
      }
    }
  }
}

class _QuickAddMotionService implements QuickAddService {
  const _QuickAddMotionService(this.create);

  final Future<String> Function() create;

  @override
  Future<String> createTask(
    String input, {
    String? description,
    String? parentId,
    String? projectId,
    String? sectionId,
    int? priority,
    DateTime? defaultDate,
    TaskSchedule? defaultSchedule,
    String? kanbanStatusId,
  }) => create();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _quickAddMotionApp(
  QuickAddService service, {
  bool disableAnimations = false,
  ValueChanged<List<String>>? onTaskCreated,
}) {
  return ProviderScope(
    overrides: [
      projectsProvider.overrideWith((ref) => Stream.value(const [])),
      labelsProvider.overrideWith((ref) => Stream.value(const [])),
      quickAddHintTextProvider.overrideWithValue(null),
      quickAddServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Scaffold(
        body: QuickAddBar(
          submitButtonKey: const Key('quick-add-motion-submit'),
          onTaskCreated: onTaskCreated,
        ),
      ),
    ),
  );
}

class _FunctionHttpClient extends http.BaseClient {
  Map<String, Object?>? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    body = Map<String, Object?>.from(
      jsonDecode(await request.finalize().bytesToString()) as Map,
    );
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'ok': true,
            'tasks': [
              {'quickAdd': 'Buy milk'},
            ],
          }),
        ),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _FakeTaskDecomposer implements TaskDecomposer {
  const _FakeTaskDecomposer(this.tasks);

  final List<DecomposedTaskDraft> tasks;

  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) async {
    return tasks;
  }
}

class _WaitingTaskDecomposer implements TaskDecomposer {
  final _completer = Completer<List<DecomposedTaskDraft>>();
  final transcripts = <String>[];

  void complete(List<DecomposedTaskDraft> tasks) {
    _completer.complete(tasks);
  }

  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) {
    transcripts.add(transcript);
    return _completer.future;
  }
}

class _RecordingSmartTaskDecomposer implements TaskDecomposer {
  final smartModes = <bool>[];

  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) async {
    smartModes.add(smartMode);
    return const [DecomposedTaskDraft(quickAdd: 'Buy milk')];
  }
}

class _FlakyTaskDecomposer implements TaskDecomposer {
  var calls = 0;

  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) async {
    calls += 1;
    if (calls == 1) {
      throw const TaskDecompositionException('temporary failure');
    }
    return const [DecomposedTaskDraft(quickAdd: 'Buy milk tomorrow')];
  }
}

class _FakeRecordedRecognizer
    implements RecordedVoiceRecognizer, RecordedVoiceAmplitudeSource {
  _FakeRecordedRecognizer({
    required this.transcript,
    this.amplitudeDbfs = const Stream<double>.empty(),
    this.startError,
  });

  final VoiceRecognitionTranscript transcript;
  @override
  final Stream<double> amplitudeDbfs;
  final Object? startError;
  var startCalls = 0;
  var stopCalls = 0;
  var cancelCalls = 0;

  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    startCalls += 1;
    if (startError != null) {
      throw startError!;
    }
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) async {
    stopCalls += 1;
    return transcript;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  void dispose() {}
}
