import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/voice_panel_motion.dart';

void main() {
  testWidgets('drag and keyboard snap inside safe and reserved screen edges', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var stopped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            viewPadding: EdgeInsets.only(top: 24, bottom: 20),
          ),
          child: VoicePanelMotion(
            expanded: false,
            reservedInsets: const EdgeInsets.only(bottom: 50),
            panel: const SizedBox(height: 280),
            indicator: const Icon(Icons.mic),
            stopButton: IconButton(
              key: const Key('stop'),
              onPressed: () => stopped++,
              icon: const Icon(Icons.stop),
            ),
            expandButton: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.open_in_full),
            ),
            onCollapse: () {},
            onExpand: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final capsule = find.byKey(const Key('voice-mini-panel'));
    final handle = find.byKey(const Key('voice-drag-handle'));
    expect(tester.getRect(capsule), const Rect.fromLTWH(616, 470, 168, 64));

    await tester.tap(find.byKey(const Key('stop')));
    expect(stopped, 1);
    await tester.drag(handle, const Offset(-650, -500));
    await tester.pumpAndSettle();
    expect(tester.getRect(capsule), const Rect.fromLTWH(16, 40, 168, 64));

    await tester.tap(handle);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.getRect(capsule), const Rect.fromLTWH(616, 40, 168, 64));

    await tester.binding.setSurfaceSize(const Size(500, 400));
    await tester.pump();
    expect(tester.getRect(capsule).right, lessThanOrEqualTo(484));
    await tester.pumpAndSettle();
    expect(tester.getRect(capsule), const Rect.fromLTWH(316, 40, 168, 64));
    // The release stays in the top-right quarter; its velocity chooses bottom-left.
    await tester.fling(handle, const Offset(-70, 70), 2000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final settlingPosition = tester.getTopLeft(capsule);
    final interruptedDrag = await tester.startGesture(tester.getCenter(handle));
    await interruptedDrag.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(tester.getTopLeft(capsule), settlingPosition);
    await interruptedDrag.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(capsule), const Rect.fromLTWH(16, 270, 168, 64));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapse retains editing state and Escape collapses expanded UI',
    (tester) async {
      final expanded = ValueNotifier(true);
      addTearDown(expanded.dispose);
      void setExpanded(bool value) {
        FocusManager.instance.primaryFocus?.unfocus();
        expanded.value = value;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: expanded,
            builder: (context, value, _) => VoicePanelMotion(
              expanded: value,
              panel: const SizedBox(
                height: 280,
                child: TextField(key: Key('editor')),
              ),
              indicator: const Icon(Icons.mic),
              stopButton: const IconButton(
                onPressed: null,
                icon: Icon(Icons.stop),
              ),
              expandButton: IconButton(
                key: const Key('expand'),
                onPressed: () => setExpanded(true),
                icon: const Icon(Icons.open_in_full),
              ),
              onCollapse: () => setExpanded(false),
              onExpand: () => setExpanded(true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editor = find.byKey(const Key('editor'));
      final editorState = tester.state(editor);
      expect(tester.getRect(editor), const Rect.fromLTWH(80, 304, 640, 280));
      await tester.enterText(editor, 'Keep this draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(expanded.value, isFalse);
      expect(
        tester.state(find.byKey(const Key('editor'), skipOffstage: false)),
        same(editorState),
      );
      await tester.tap(find.byKey(const Key('expand')));
      await tester.pumpAndSettle();
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(tester.state(editor), same(editorState));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(expanded.value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
