import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_details.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_dialog.dart';

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
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusPresetsProvider.overrideWith((ref) => Stream.value([])),
        projectsProvider.overrideWith(
          (ref) => Stream.value(const <ProjectItem>[]),
        ),
        labelsProvider.overrideWith((ref) => Stream.value(const <LabelItem>[])),
        if (saving)
          quickAddViewModelProvider.overrideWith2(_SavingQuickAdd.new),
      ],
      child: MaterialApp(
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
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showQuickAddDialog(context),
              child: const Text('Open'),
            ),
          ),
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
