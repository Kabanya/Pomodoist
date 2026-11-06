import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_details.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_dialog.dart';
import 'package:pomodoist/utils/clock.dart';

import 'support/test_app.dart';

const _header = Key('quick-add-sheet-header');
const _input = Key('sidebar-quick-add-input');
const _submit = Key('sidebar-quick-add-submit');

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double keyboard = 0,
  double textScale = 1,
  bool reduceMotion = false,
  bool saving = false,
  Brightness brightness = Brightness.dark,
  Locale locale = const Locale('en'),
  DateTime? defaultDate,
  String location = '/inbox',
  String initialText = '',
  Clock? clock,
  QuickAddUseCase? useCase,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: Uri.parse(location).path,
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => showQuickAddDialog(
              context,
              defaultDate: defaultDate,
              initialText: initialText,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (clock != null) clockProvider.overrideWithValue(clock),
        if (useCase != null) quickAddUseCaseProvider.overrideWithValue(useCase),
        focusPresetsProvider.overrideWith((ref) => Stream.value([])),
        projectsProvider.overrideWith(
          (ref) => Stream.value(const <ProjectItem>[]),
        ),
        labelsProvider.overrideWith((ref) => Stream.value(const <LabelItem>[])),
        if (saving)
          quickAddViewModelProvider.overrideWith2(_SavingQuickAdd.new),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: testAppBuilder(context, child),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Rect _sheet(WidgetTester tester) =>
    tester.getRect(find.byType(QuickAddComposer));

Future<void> _swipe(WidgetTester tester, Offset offset) async {
  await tester.dragFrom(
    tester.getTopLeft(find.byKey(_header)) + const Offset(24, 24),
    offset,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadTestAppResources);

  for (final width in [390.0, 1000.0]) {
    for (final (location, expected, text) in [
      ('/today', DateTime(2026, 11, 6), 'Today '),
      ('/today?task=selected', DateTime(2026, 11, 6), 'Today '),
      ('/upcoming?date=2026-11-13', DateTime(2026, 11, 13), '2026-11-13 '),
      ('/upcoming?date=2024-02-29', DateTime(2024, 2, 29), '2024-02-29 '),
      ('/upcoming', DateTime(2026, 11, 6), 'Today '),
      ('/upcoming?date=2026-02-30', DateTime(2026, 11, 6), 'Today '),
      ('/upcoming?date=2026-13-01', DateTime(2026, 11, 6), 'Today '),
      ('/upcoming?date=2026-11-00', DateTime(2026, 11, 6), 'Today '),
      ('/upcoming?date=2026-1-3', DateTime(2026, 11, 6), 'Today '),
      ('/upcoming?date=invalid', DateTime(2026, 11, 6), 'Today '),
      ('/inbox', null, ''),
      ('/calendar?date=2026-11-13', null, ''),
    ]) {
      testWidgets('Quick Add inherits date from $location at $width px', (
        tester,
      ) async {
        await _open(
          tester,
          location: location,
          size: Size(width, 900),
          clock: FixedClock(DateTime(2026, 11, 6, 17, 45)),
        );
        expect(
          tester
              .widget<QuickAddComposer>(find.byType(QuickAddComposer))
              .defaultDate,
          expected,
        );
        final controller = tester
            .widget<TextField>(find.byKey(_input))
            .controller!;
        expect(controller.text, text);
        expect(
          controller.selection,
          TextSelection.collapsed(offset: text.length),
        );
        final details = tester.widget<QuickAddDetails>(
          find.byType(QuickAddDetails),
        );
        expect(
          const QuickAddParser()
              .parse(
                controller.text,
                now: DateTime(2026, 11, 6),
                defaultDate: details.defaultDate,
              )
              .schedule
              ?.displayDate,
          expected,
        );
      });
    }
  }

  testWidgets('explicit default date overrides the selected Upcoming day', (
    tester,
  ) async {
    await _open(
      tester,
      location: '/upcoming?date=2026-11-13',
      defaultDate: DateTime(2026, 11, 20),
    );
    expect(
      tester
          .widget<QuickAddComposer>(find.byType(QuickAddComposer))
          .defaultDate,
      DateTime(2026, 11, 20),
    );
    expect(
      tester.widget<TextField>(find.byKey(_input)).controller!.text,
      '2026-11-20 ',
    );
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('Today prefill is recognized in $locale', (tester) async {
      await _open(
        tester,
        location: '/today',
        locale: locale,
        clock: FixedClock(DateTime(2026, 11, 6)),
      );
      final context = tester.element(find.byKey(_input));
      final controller = tester
          .widget<TextField>(find.byKey(_input))
          .controller!;
      expect(controller.text, '${AppLocalizations.of(context).today} ');
      final parsed = const QuickAddParser().parse(
        '${controller.text}Report',
        now: DateTime(2026, 11, 6),
      );
      expect(parsed.content, 'Report');
      expect(parsed.schedule!.displayDate, DateTime(2026, 11, 6));
    });
  }

  testWidgets('existing initial text keeps its inherited date', (tester) async {
    await _open(
      tester,
      location: '/today',
      initialText: 'Report tomorrow',
      clock: FixedClock(DateTime(2026, 11, 6)),
    );
    expect(
      tester.widget<TextField>(find.byKey(_input)).controller!.text,
      'Report tomorrow',
    );
    expect(
      tester.widget<QuickAddDetails>(find.byType(QuickAddDetails)).defaultDate,
      DateTime(2026, 11, 6),
    );
  });

  testWidgets('reopening and resizing preserve an edited draft', (
    tester,
  ) async {
    await _open(tester, location: '/today');
    await tester.enterText(find.byKey(_input), 'Report');
    final context = tester.element(find.byKey(_input));
    showQuickAddDialog(context);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 900);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddComposer), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_input)).controller!.text,
      'Report',
    );
    expect(
      tester.widget<QuickAddDetails>(find.byType(QuickAddDetails)).defaultDate,
      isNull,
    );
  });

  for (final (input, expected, detailed) in <(String?, DateTime?, bool)>[
    (null, DateTime(2026, 11, 13), false),
    ('tomorrow Report', DateTime(2026, 11, 7), false),
    ('Report', null, false),
    ('Report', null, true),
  ]) {
    testWidgets(
      'prefilled draft saves $input with date $expected (detailed: $detailed)',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await tester.runAsync(db.ensureSeedData);
        final outbox = DriftOutboxService(db);
        final repository = DriftTaskRepository(db, outbox);
        await _open(
          tester,
          location: '/upcoming?date=2026-11-13',
          size: const Size(1000, 900),
          clock: FixedClock(DateTime(2026, 11, 6)),
          useCase: QuickAddUseCase(
            parser: const QuickAddParser(),
            taskRepository: repository,
            projectRepository: DriftProjectRepository(db, outbox),
            now: () => DateTime(2026, 11, 6),
          ),
        );
        final controller = tester
            .widget<TextField>(find.byKey(_input))
            .controller!;
        await tester.enterText(
          find.byKey(_input),
          input ?? '${controller.text}Report',
        );
        await tester.pumpAndSettle();
        if (detailed) {
          await tester.tap(find.byKey(const Key('quick-add-open-editor')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
        final saved = await tester.runAsync(() async {
          final task = repository
              .watchTasks(const TaskQuery.all())
              .firstWhere((tasks) => tasks.isNotEmpty);
          await tester.tap(
            find.byKey(detailed ? const Key('task-create-submit') : _submit),
          );
          return (await task.timeout(const Duration(seconds: 5))).single;
        });
        expect(saved!.content, 'Report');
        expect(saved.schedule?.displayDate, expected);
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'schedule menu saves one draft and time offsets keep the task date',
    (tester) async {
      await _open(tester, size: const Size(1000, 900));
      const original = 'Report 2026-11-02 23:55 90m p2';
      await tester.enterText(find.byKey(_input), original);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byKey(_input))
          .controller!;
      Future<void> menu() async {
        await tester.tap(
          find
              .descendant(
                of: find.byType(AppDateTimePicker),
                matching: find.byType(ShadButton),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }

      await menu();
      expect(find.text('Date and time'), findsOneWidget);
      await tester.tap(find.text('Pick date'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('picker-date-input')),
        '11/04/2026',
      );
      expect(controller.text, original);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.text, original);
      await menu();
      await tester.tap(find.text('Pick date'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('picker-date-input')),
        '11/04/2026',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      TaskSchedule parsed() => const QuickAddParser()
          .parse(controller.text, now: DateTime(2026, 11, 2))
          .schedule!;
      expect(parsed().displayDate, DateTime(2026, 11, 4));
      expect(parsed().duration, const Duration(minutes: 90));
      expect(parsed().start!.toLocal().hour, 23);
      expect(controller.text, contains('p2'));
      await menu();
      await tester.tap(find.text('Change time'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('picker-offset-15')));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(parsed().displayDate, DateTime(2026, 11, 4));
      expect(parsed().start!.toLocal(), DateTime(2026, 11, 4, 0, 10));
      expect(parsed().duration, const Duration(minutes: 90));
      await menu();
      await tester.tap(
        find.text(
          AppLocalizations.of(tester.element(find.byKey(_input))).allDay,
        ),
      );
      await tester.pumpAndSettle();
      expect(parsed().isAllDay, isTrue);
      expect(parsed().displayDate, DateTime(2026, 11, 4));
      await menu();
      await tester.tap(find.text('Use default'));
      await tester.pumpAndSettle();
      expect(controller.text.trim().split(RegExp(r'\s+')), ['Report', 'p2']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reset returns Quick Add to its inherited date', (tester) async {
    await _open(
      tester,
      size: const Size(1000, 900),
      defaultDate: DateTime(2026, 11, 2),
    );
    await tester.enterText(find.byKey(_input), 'Report 2026-11-04');
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(find.byKey(_input)).controller!;
    await tester.tap(
      find
          .descendant(
            of: find.byType(AppDateTimePicker),
            matching: find.byType(ShadButton),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use default'));
    await tester.pumpAndSettle();
    final parsed = const QuickAddParser().parse(
      controller.text,
      now: DateTime(2026, 11, 1),
      defaultDate: DateTime(2026, 11, 2),
    );
    expect(parsed.schedule!.displayDate, DateTime(2026, 11, 2));
    expect(controller.text.trim(), 'Report');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'priority menu labels levels and preserves other draft metadata',
    (tester) async {
      await _open(tester);
      await tester.enterText(find.byKey(_input), 'Prepare report #Work p3 2p');
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byKey(_input))
          .controller!;
      await tester.tap(find.byIcon(LucideIcons.flag));
      await tester.pumpAndSettle();
      for (final label in ['Urgent', 'High', 'Normal', 'Low']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Use default'), findsNothing);
      for (var priority = 1; priority <= 4; priority++) {
        expect(find.text('Priority $priority'), findsOneWidget);
      }
      await tester.tap(find.text('Priority 1'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Prepare report #Work p1 2p');
      await tester.tap(find.byTooltip('Priority 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Priority 4'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Prepare report #Work p4 2p');
      expect(find.text('P4'), findsNothing);
      expect(find.byTooltip('Priority 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('priority menu supports scaled Russian text in $brightness', (
      tester,
    ) async {
      await _open(
        tester,
        size: const Size(320, 844),
        textScale: 2,
        brightness: brightness,
        locale: const Locale('ru'),
      );
      await tester.enterText(find.byKey(_input), 'Отчёт p3');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(LucideIcons.flag));
      await tester.tap(find.byIcon(LucideIcons.flag));
      await tester.pumpAndSettle();
      expect(find.text('Обычный'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Приоритет 4'));
      await tester.tap(find.text('Приоритет 4'));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byKey(_input))
          .controller!;
      expect(controller.text, 'Отчёт p4');
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0]) {
      testWidgets('mobile icon toolbar fits $width px in $brightness', (
        tester,
      ) async {
        await _open(
          tester,
          size: Size(width, 844),
          keyboard: 280,
          textScale: 2,
          brightness: brightness,
          initialText: 'Review p4',
        );
        await tester.pumpAndSettle();
        final buttons = find.descendant(
          of: find.byType(QuickAddDetails),
          matching: find.byType(ShadButton),
        );
        expect(buttons, findsNWidgets(5));
        expect(find.text('P4'), findsNothing);
        expect(find.byTooltip('Priority 4'), findsOneWidget);
        final rects = [
          for (final element in buttons.evaluate())
            tester.getRect(find.byWidget(element.widget)),
        ];
        for (final rect in rects) {
          expect(rect.size, const Size(48, 48));
          expect(rect.top, rects.first.top);
          expect(rect.left, greaterThanOrEqualTo(20));
          expect(rect.right, lessThanOrEqualTo(width - 20));
          expect(rect.bottom, lessThanOrEqualTo(844 - 280));
        }
        for (final button in tester.widgetList<ShadButton>(buttons)) {
          expect(button.child, isNull);
          expect(
            button.backgroundColor,
            tester.element(find.byKey(_input)).appColors.surfaceTint,
          );
        }
        await tester.tap(find.byIcon(LucideIcons.timer));
        await tester.pumpAndSettle();
        expect(find.byType(PageView), findsOneWidget);
        expect(tester.getSize(find.byType(PageView)).width, greaterThan(100));
        expect(find.byIcon(LucideIcons.flag), findsOneWidget);
        await tester.tap(find.byTooltip('Increase estimate'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byKey(_input)).controller!.text,
          contains('2p'),
        );
        await tester.tap(find.byIcon(LucideIcons.timer));
        await tester.pumpAndSettle();
        expect(find.byType(PageView), findsNothing);
        await tester.tap(find.byKey(const Key('quick-add-comment-toggle')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('quick-add-comment-input')),
          'Keep this comment',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.byType(Badge), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'priority selection keeps input stable through keyboard transitions',
    (tester) async {
      await _open(tester, keyboard: 280);
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.padding = const FakeViewPadding(top: 44);
      await tester.enterText(find.byKey(_input), 'Review p4');
      await tester.pumpAndSettle();
      final inputTop = tester.getTopLeft(find.byKey(_input)).dy;
      final headerTop = tester.getTopLeft(find.byKey(_header)).dy;
      await tester.tap(find.byTooltip('Priority 4'));
      await tester.pumpAndSettle();
      for (final inset in [220.0, 100.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        tester.view.padding = FakeViewPadding(
          top: 44,
          bottom: inset == 0 ? 34 : 0,
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(_input)).dy, closeTo(inputTop, 1));
        expect(
          tester.getTopLeft(find.byKey(_header)).dy,
          closeTo(headerTop, 1),
        );
      }
      await tester.tap(find.text('Priority 1'));
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(find.byKey(_input));
      expect(input.controller!.text, 'Review p1');
      await tester.tap(find.byKey(_input));
      for (final inset in [100.0, 220.0, 280.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        tester.view.padding = const FakeViewPadding(top: 44);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(_input)).dy, closeTo(inputTop, 1));
      }
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(700, 430);
      await tester.pumpAndSettle();
      expect(_sheet(tester).height, lessThan(350));
      expect(_sheet(tester).bottom, lessThanOrEqualTo(430));
      expect(
        tester.widget<TextField>(find.byKey(_input)).controller,
        same(input.controller),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final expanded in [false, true]) {
    testWidgets('mobile metadata opens at the bottom, expanded=$expanded', (
      tester,
    ) async {
      await _open(
        tester,
        keyboard: 280,
        initialText: 'Review',
        reduceMotion: true,
      );
      if (expanded) await _swipe(tester, const Offset(0, -100));
      await tester.tap(find.byIcon(LucideIcons.calendar));
      await tester.pump();
      await tester.pump();
      Rect menu() => tester.getRect(
        find
            .ancestor(
              of: find.text('Date and time'),
              matching: find.byType(ShadDecorator),
            )
            .first,
      );
      // The shared popup enters with a 4 px translation, without changing sides.
      expect(menu().bottom, closeTo(844 - 280 - 12, 4.1));
      await tester.pumpAndSettle();
      expect(menu().bottom, closeTo(844 - 280 - 12, 1));
      for (final inset in [140.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pumpAndSettle();
        expect(menu().bottom, closeTo(844 - inset - 12, 1));
      }
      await tester.tap(find.text('Pick date'));
      await tester.pumpAndSettle();
      final datePanel = find
          .ancestor(
            of: find.byKey(const Key('picker-date-input')),
            matching: find.byType(ShadDecorator),
          )
          .last;
      expect(tester.getRect(datePanel).bottom, closeTo(832, 1));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.hash));
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(ShadInput),
        matching: find.byType(EditableText),
      );
      expect(search, findsOneWidget);
      expect(tester.widget<EditableText>(search).focusNode.hasFocus, isFalse);
      final projectPanel = find
          .ancestor(of: search, matching: find.byType(ShadDecorator))
          .last;
      expect(tester.getRect(projectPanel).bottom, closeTo(832, 1));
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.getRect(projectPanel).bottom, closeTo(552, 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty sheet is compact and metadata still follows the input', (
    tester,
  ) async {
    await _open(tester);
    expect(_sheet(tester).height, lessThan(230));
    expect(tester.getSize(find.byType(QuickAddDetails)).height, 0);
    final emptyHeight = _sheet(tester).height;
    await tester.enterText(
      find.byKey(_input),
      'Prepare report tomorrow #Work 2p',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-add-comment-toggle')), findsOneWidget);
    expect(tester.getSize(find.byType(QuickAddDetails)).height, greaterThan(0));
    expect(_sheet(tester).height, greaterThan(emptyHeight));
    await tester.enterText(find.byKey(_input), '');
    await tester.pumpAndSettle();
    expect(_sheet(tester).height, closeTo(emptyHeight, 1));
  });

  testWidgets('swipe up retains draft, selection and focus and pins actions', (
    tester,
  ) async {
    await _open(tester);
    await tester.enterText(
      find.byKey(_input),
      'Prepare report tomorrow #Work 2p',
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(_input));
    field.controller!.selection = const TextSelection(
      baseOffset: 2,
      extentOffset: 6,
    );
    final value = field.controller!.value;
    await _swipe(tester, const Offset(0, -100));
    expect(_sheet(tester).top, closeTo(0, 1));
    expect(_sheet(tester).height, closeTo(844, 1));
    final expanded = tester.widget<TextField>(find.byKey(_input));
    expect(expanded.controller, same(field.controller));
    expect(expanded.controller!.value, value);
    expect(expanded.focusNode!.hasFocus, isTrue);
    expect(tester.getBottomRight(find.byKey(_submit)).dy, greaterThan(800));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(_sheet(tester).bottom, closeTo(544, 1));
    expect(
      tester.widget<TextField>(find.byKey(_input)).controller!.value,
      value,
    );
    await _swipe(tester, const Offset(0, 100));
    expect(find.byType(QuickAddComposer), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(_sheet(tester).height, lessThan(230));
  });

  testWidgets('downward swipe closes compact sheet', (tester) async {
    await _open(tester);
    await _swipe(tester, const Offset(0, 100));
    expect(find.byType(QuickAddComposer), findsNothing);
  });

  testWidgets('a 48 pixel upward swipe expands only after release', (
    tester,
  ) async {
    await _open(tester);
    final initial = _sheet(tester);
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(_header)) + const Offset(24, 24),
    );
    await gesture.moveBy(const Offset(0, -48));
    await tester.pump();
    expect(_sheet(tester), initial);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_sheet(tester).height, closeTo(844, 1));
  });

  testWidgets('header follows the visible sheet top during expansion', (
    tester,
  ) async {
    await _open(tester);
    final compactHeight = _sheet(tester).height;
    await tester.tap(find.byKey(const Key('quick-add-sheet-expand')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final header = tester.getRect(find.byKey(_header));
    expect(header.top, greaterThan(0));
    expect(header.top, lessThan(844 - compactHeight));
    expect(tester.hitTestOnBinding(header.center).path, isNotEmpty);
    expect(_sheet(tester).top, closeTo(header.top, 1));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'short, horizontal and cancelled gestures leave sheet unchanged',
    (tester) async {
      await _open(tester);
      final initial = _sheet(tester);
      await _swipe(tester, const Offset(0, -30));
      expect(_sheet(tester), initial);
      await _swipe(tester, const Offset(120, -60));
      expect(_sheet(tester), initial);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_header)),
      );
      await gesture.moveBy(const Offset(0, -100));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_sheet(tester), initial);
    },
  );

  testWidgets('comment draft and scrolling do not trigger panel gestures', (
    tester,
  ) async {
    await _open(tester);
    await tester.enterText(find.byKey(_input), 'Prepare report');
    await tester.pumpAndSettle();
    final compact = _sheet(tester);
    await tester.drag(find.byType(QuickAddDetails), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(_sheet(tester), compact);
    await tester.drag(find.byKey(_input), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(_sheet(tester), compact);
    await tester.tap(find.byKey(const Key('quick-add-comment-toggle')));
    await tester.pumpAndSettle();
    final comment = find.byKey(const Key('quick-add-comment-input'));
    await tester.enterText(comment, 'Bring originals\nSecond line\nThird line');
    final controller = tester.widget<TextField>(comment).controller;
    await _swipe(tester, const Offset(0, -100));
    expect(tester.widget<TextField>(comment).controller, same(controller));
    expect(controller!.text, 'Bring originals\nSecond line\nThird line');
    final headerTop = tester.getTopLeft(find.byKey(_header));
    final submitBottom = tester.getBottomRight(find.byKey(_submit));
    await tester.drag(comment, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddComposer), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(_header)), headerTop);
    expect(tester.getBottomRight(find.byKey(_submit)), submitBottom);
  });

  for (final brightness in Brightness.values) {
    testWidgets('small screen, keyboard and scaled text fit in $brightness', (
      tester,
    ) async {
      await _open(
        tester,
        size: const Size(320, 568),
        keyboard: 260,
        textScale: 1.5,
        brightness: brightness,
      );
      await tester.enterText(
        find.byKey(_input),
        'Prepare report tomorrow #Work 2p',
      );
      await tester.pumpAndSettle();
      await _swipe(tester, const Offset(0, -100));
      expect(_sheet(tester).bottom, closeTo(308, 1));
      expect(_sheet(tester).top, closeTo(0, 1));
      expect(
        tester.getBottomRight(find.byKey(_submit)).dy,
        lessThanOrEqualTo(308),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'handle expands accessibly without animation under Reduce Motion',
    (tester) async {
      await _open(tester, reduceMotion: true);
      final handle = find.byKey(const Key('quick-add-sheet-expand'));
      expect(
        tester.getSemantics(handle).getSemanticsData().label,
        'Expand editor',
      );
      await tester.tap(handle);
      await tester.pump();
      expect(_sheet(tester).height, closeTo(844, 1));
    },
  );

  testWidgets('header gestures cannot dismiss or expand while saving', (
    tester,
  ) async {
    await _open(tester, saving: true);
    final initial = _sheet(tester);
    await _swipe(tester, const Offset(0, -100));
    expect(_sheet(tester), initial);
    await _swipe(tester, const Offset(0, 100));
    expect(_sheet(tester), initial);
  });
}

class _SavingQuickAdd extends QuickAddViewModel {
  _SavingQuickAdd(super.identity);

  @override
  QuickAddState build() =>
      (draft: '', description: '', result: const AsyncLoading());
}
