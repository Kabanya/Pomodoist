import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_preferences_repository_impl.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/widgets/app_context_menu_region.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_settings.dart';
import 'pomo_controller_test.dart' as fixtures;
import 'package:pomodoist/ui/pomo/widgets/pomo_geometry.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_stage_canvas.dart';

void main() {
  for (final (label, stage, control, viewport) in [
    (
      'companion at 2x',
      const Size(328, 328),
      PomoLayout(1).pet,
      const Size(656, 656),
    ),
    (
      'compact panel at 2x',
      const Size(320, 256),
      const Rect.fromLTWH(16, 80, 48, 48),
      const Size(640, 512),
    ),
    (
      'fractional nonuniform viewport',
      const Size(360, 354),
      const Rect.fromLTWH(61.5, 75.25, 48, 48),
      const Size(517.5, 442.5),
    ),
  ]) {
    testWidgets('GNOME $label scales drawing and pointer hits together', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var taps = 0;
      final target = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: viewport,
              child: PomoStageCanvas(
                enabled: true,
                stageSize: stage,
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: control,
                      child: GestureDetector(
                        key: target,
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps++,
                        child: const ColoredBox(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final box = target.currentContext!.findRenderObject()! as RenderBox;
      final topLeft = box.localToGlobal(Offset.zero);
      final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
      final sx = viewport.width / stage.width,
          sy = viewport.height / stage.height;
      expect(topLeft.dx, closeTo(control.left * sx, .001));
      expect(topLeft.dy, closeTo(control.top * sy, .001));
      expect(bottomRight.dx - topLeft.dx, closeTo(control.width * sx, .001));
      expect(bottomRight.dy - topLeft.dy, closeTo(control.height * sy, .001));
      await tester.tapAt(
        Offset(control.center.dx * sx, control.center.dy * sy),
      );
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'fitted compact panel timer switch keeps the real preference action',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 512));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preferences = LocalPomoPreferencesRepository(
        fixtures.MemoryPreferences(),
      );
      await preferences.load();
      final controller = PomoController(preferences, fixtures.Host());
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pomoControllerProvider.overrideWith((ref) => controller)],
          child: ShadApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PomoStageCanvas(
              enabled: true,
              stageSize: Size(320, 256),
              child: Material(child: PomoTimerControl()),
            ),
          ),
        ),
      );
      final box = tester.renderObject<RenderBox>(find.byType(ShadSwitch));
      final start = box.localToGlobal(Offset.zero);
      final end = box.localToGlobal(box.size.bottomRight(Offset.zero));
      expect(end.dx - start.dx, closeTo(box.size.width * 2, .001));
      expect(end.dy - start.dy, closeTo(box.size.height * 2, .001));
      expect(preferences.state.showTimer, true);
      await tester.tap(find.byType(ShadSwitch));
      await tester.pump();
      expect(preferences.state.showTimer, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'real companion context menu scales row, font and action with the stage',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 512));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final menuRow = GlobalKey(), trigger = GlobalKey(), canvas = GlobalKey();
      var taps = 0;
      Widget app(Size stageSize) => ShadApp.custom(
        appBuilder: (_) => MaterialApp(
          builder: (context, child) => PomoStageCanvas(
            enabled: true,
            stageSize: stageSize,
            canvasKey: canvas,
            child: ShadAppBuilder(child: child),
          ),
          home: Material(
            child: Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: AppContextMenuRegion(
                  enableLongPress: false,
                  items: [
                    ShadContextMenuItem(
                      key: menuRow,
                      height: 44,
                      onPressed: () => taps++,
                      child: const Text('Open application'),
                    ),
                  ],
                  child: ColoredBox(key: trigger, color: Colors.red),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(const Size(320, 256)));
      final menuState = tester.state(find.byType(AppContextMenuRegion));
      await tester.tap(
        find.byKey(trigger),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final box = menuRow.currentContext!.findRenderObject()! as RenderBox;
      final height =
          box.localToGlobal(Offset(0, box.size.height)).dy -
          box.localToGlobal(Offset.zero).dy;
      expect(height, closeTo(88, .001));
      final text = tester.renderObject<RenderBox>(
        find.text('Open application'),
      );
      expect(text.getTransformTo(null).entry(0, 0), closeTo(2, .001));
      expect(MediaQuery.sizeOf(menuRow.currentContext!), const Size(320, 256));
      await tester.pumpWidget(app(const Size(336, 272)));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AppContextMenuRegion)), same(menuState));
      expect(find.text('Open application'), findsOneWidget);
      await tester.tap(find.text('Open application'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (label, viewport) in [
    ('2x', const Size(520, 400)),
    ('fractional nonuniform', const Size(390, 250)),
  ]) {
    testWidgets(
      '$label overlay menu regions include both rows and clip to stage',
      (tester) async {
        final canvas = GlobalKey(),
            first = GlobalKey(),
            second = GlobalKey(),
            clipped = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: viewport,
                child: PomoStageCanvas(
                  enabled: true,
                  stageSize: const Size(260, 200),
                  canvasKey: canvas,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 100,
                        top: 60,
                        width: 100,
                        height: 44,
                        child: SizedBox(key: first),
                      ),
                      Positioned(
                        left: 100,
                        top: 104,
                        width: 100,
                        height: 44,
                        child: SizedBox(key: second),
                      ),
                      Positioned(
                        left: -5,
                        top: -5,
                        width: 40,
                        height: 30,
                        child: SizedBox(key: clipped),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final canvasBox =
            canvas.currentContext!.findRenderObject()! as RenderBox;
        final bounds = pomoMenuBoundsInCanvas(
          canvasBox,
          [
            first,
            second,
          ].map((key) => key.currentContext!.findRenderObject()! as RenderBox),
        )!;
        expect(bounds, const Rect.fromLTRB(92, 52, 208, 156));
        final clippedBounds = pomoMenuBoundsInCanvas(canvasBox, [
          clipped.currentContext!.findRenderObject()! as RenderBox,
        ])!;
        expect(clippedBounds, const Rect.fromLTRB(0, 0, 43, 33));
      },
    );
  }

  testWidgets(
    'other placement backends retain their existing canvas constraints',
    (tester) async {
      final target = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: PomoStageCanvas(
              enabled: false,
              stageSize: const Size(260, 200),
              child: SizedBox.expand(key: target),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(target)), const Size(800, 600));
      expect(find.byType(FittedBox), findsNothing);
    },
  );
}
