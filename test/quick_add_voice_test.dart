import 'dart:async';
import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:app_voice/app_voice.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/onboarding/onboarding_gate.dart';
import 'package:pomodoist/features/planning/data/task_decomposer.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/quick_add_bar.dart';
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
    await tester.pump(const Duration(milliseconds: 239));
    expect(find.byKey(const Key('quick-add-submit-success')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const Key('quick-add-submit-idle')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 1));
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
    await tester.pump(const Duration(milliseconds: 359));
    expect(find.byKey(const Key('quick-add-submit-success')), findsOneWidget);
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
    expect(find.text('0:59'), findsOneWidget);
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
    expect(find.text('0:58'), findsOneWidget);

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
