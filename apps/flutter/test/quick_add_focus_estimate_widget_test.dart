import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_focus_estimate.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';

import 'support/test_app.dart';

void main() {
  setUpAll(loadTestAppResources);

  Future<void> mount(
    WidgetTester tester, {
    int? initial = 3,
    ValueChanged<int?>? onChanged,
    bool enabled = true,
    bool dark = true,
    double scale = 1,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var estimate = initial;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => testAppBuilder(
          context,
          MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: const EdgeInsets.only(bottom: 280),
            ),
            child: child!,
          ),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: QuickAddFocusEstimateChip(
                  estimate: estimate,
                  manual: estimate != null,
                  workSeconds: 25 * 60,
                  enabled: enabled,
                  touchTargets: true,
                  onChanged: (value) {
                    onChanged?.call(value);
                    setState(() => estimate = value);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(QuickAddFocusEstimateChip)),
    );
    await tester.tap(
      find.text(
        initial == null
            ? l10n.quickAddFocusEstimate
            : l10n.quickAddEstimatedPomodoros(initial),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'touch estimate stays inline above the keyboard and edits by swipe',
    (tester) async {
      final changes = <int?>[];
      await mount(tester, onChanged: changes.add);
      expect(changes, isEmpty);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      final wheel = tester.getRect(find.byType(PageView));
      expect(wheel.top, greaterThan(100));
      expect(wheel.bottom, lessThanOrEqualTo(844 - 280));
      await tester.drag(find.byType(PageView), const Offset(-64, 0));
      await tester.pumpAndSettle();
      expect(changes.last, greaterThan(3));
      expect(find.textContaining('${changes.last! * 25} min'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom entry validates 1–999 and clear restores no estimate', (
    tester,
  ) async {
    final changes = <int?>[];
    await mount(tester, onChanged: changes.add);
    await tester.tap(find.text('Enter number'));
    await tester.pumpAndSettle();
    for (final invalid in ['0', '1000', '']) {
      await tester.enterText(find.byType(EditableText), invalid);
      await tester.pump();
      expect(find.text('Enter a whole number from 1 to 999.'), findsOneWidget);
      expect(changes, isEmpty);
    }
    await tester.enterText(find.byType(EditableText), '999');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(changes, [999]);
    expect(find.textContaining('24975'), findsOneWidget);
    await tester.tap(find.text('Clear estimate'));
    await tester.pumpAndSettle();
    expect(changes, [999, null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tapping the proposed first interval explicitly sets an estimate',
    (tester) async {
      final changes = <int?>[];
      await mount(tester, initial: null, onChanged: changes.add);
      expect(changes, isEmpty);
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      expect(changes, [1]);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'large text retains usable selection in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        final changes = <int?>[];
        await mount(tester, dark: dark, scale: 2, onChanged: changes.add);
        await tester.ensureVisible(find.byTooltip('Increase estimate'));
        await tester.tap(find.byTooltip('Increase estimate'));
        await tester.pumpAndSettle();
        expect(changes.last, 4);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'boundary counts and Arabic selection retain range and semantics',
    (tester) async {
      final changes = <int?>[];
      await mount(
        tester,
        initial: 999,
        locale: const Locale('ar'),
        onChanged: changes.add,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(QuickAddFocusEstimateChip)),
      );
      final increase = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.tooltip == l10n.quickAddIncreaseEstimate,
        ),
      );
      expect(increase.onPressed, isNull);
      await tester.tap(find.byTooltip(l10n.quickAddDecreaseEstimate));
      await tester.pumpAndSettle();
      expect(changes, [998]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final compact in [true, false]) {
    testWidgets(
      '${compact ? 'mobile' : 'desktop'} composer preserves task metadata while selecting',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(compact ? 390 : 1100, 844);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              focusPresetsProvider.overrideWith((_) => Stream.value([])),
              projectsProvider.overrideWith(
                (_) => Stream.value(const <ProjectItem>[]),
              ),
              labelsProvider.overrideWith(
                (_) => Stream.value(const <LabelItem>[]),
              ),
            ],
            child: MaterialApp(
              builder: testAppBuilder,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: QuickAddComposer(
                    compact: compact,
                    initialText: 'Review tomorrow p2 3p',
                    onCompleted: () {},
                    onCancel: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('3 Pomodoros'));
        await tester.tap(find.text('3 Pomodoros'));
        await tester.pumpAndSettle();
        final taskInput = tester.widget<TextField>(
          find.byKey(const Key('sidebar-quick-add-input')),
        );
        if (compact) expect(taskInput.focusNode!.hasFocus, isFalse);
        await tester.tap(find.byTooltip('Increase estimate'));
        await tester.pumpAndSettle();
        expect(taskInput.controller!.text, 'Review tomorrow p2 4p');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
