import 'package:app_voice/app_voice.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/ui/quick_add/widgets/global_quick_add_window.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/config/billing_store_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/voice_dependencies.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/billing/billing_access.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/core/view_models/app_zoom_view_model.dart';
import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';
import '../testing/fakes/fake_focus_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final zoom in [100, 150, 200]) {
    testWidgets('native height fits input and protects a full line at $zoom%', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(836, 168);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({appZoomPreferenceKey: zoom});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var minimumHeight = 0.0;
      var automatic = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            focusRepositoryProvider.overrideWithValue(FakeFocusRepository()),
          ],
          child: GlobalQuickAddWindowApp(
            onClose: () {},
            onVoiceModeChanged: (_) {},
            onHeightRequirementsChanged: (preferred, minimum, viewportHeight) {
              minimumHeight = minimum;
              final height = automatic
                  ? (preferred > minimum ? preferred : minimum)
                  : (viewportHeight > minimum ? viewportHeight : minimum);
              if ((viewportHeight - height).abs() > .1) {
                tester.view.physicalSize = Size(836, height.ceilToDouble());
              }
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ShortcutHintsBar)).height, 0);
      expect(minimumHeight, greaterThan(0));
      expect(tester.view.physicalSize.width, 836);
      final input = find.byKey(const Key('sidebar-quick-add-input'));
      Rect inputViewport() => tester.getRect(
        find
            .ancestor(of: input, matching: find.byType(SingleChildScrollView))
            .first,
      );
      final field = tester.getRect(input);
      expect(field.top, greaterThanOrEqualTo(inputViewport().top));
      expect(field.bottom, lessThanOrEqualTo(inputViewport().bottom + .1));
      automatic = false;
      tester.view.physicalSize = Size(836, minimumHeight.ceilToDouble());
      await tester.pumpAndSettle();
      const draft = 'АgjЁу';
      await tester.enterText(find.byType(EditableText), draft);
      await tester.pumpAndSettle();
      void expectFullLine() {
        final editable = tester
            .state<EditableTextState>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .renderEditable;
        final boxes = editable.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: draft.length),
        );
        expect(boxes, isNotEmpty);
        for (final box in boxes) {
          final top = editable.localToGlobal(Offset(box.left, box.top));
          final bottom = editable.localToGlobal(Offset(box.right, box.bottom));
          expect(top.dy, greaterThanOrEqualTo(inputViewport().top - .1));
          expect(bottom.dy, lessThanOrEqualTo(inputViewport().bottom + .1));
        }
      }

      expectFullLine();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ShortcutHintsBar)).height,
        greaterThan(0),
      );
      expectFullLine();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ShortcutHintsBar)).height, 0);
      await tester.tap(find.byKey(const Key('quick-add-comment-toggle')));
      await tester.pumpAndSettle();
      expectFullLine();
      await tester.tap(find.byKey(const Key('quick-add-comment-toggle')));
      await tester.pumpAndSettle();
      final oldMinimum = minimumHeight;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GlobalQuickAddWindowApp)),
      );
      await container
          .read(appZoomProvider.notifier)
          .setPercent(zoom == 200 ? 100 : 200);
      await tester.pumpAndSettle();
      await tester.runAsync(tester.binding.reassembleApplication);
      await tester.pumpAndSettle();
      expect(
        minimumHeight,
        zoom == 200 ? lessThan(oldMinimum) : greaterThan(oldMinimum),
      );
      expect(find.text(draft), findsOneWidget);
      expectFullLine();
      final oldTextMinimum = minimumHeight;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(minimumHeight, greaterThan(oldTextMinimum));
      expectFullLine();
      final add = tester.getRect(
        find.byKey(const Key('sidebar-quick-add-submit')),
      );
      expect(
        add.bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height + .1),
      );
      expect(add.top, greaterThanOrEqualTo(inputViewport().bottom));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
  testWidgets(
    'native reactivation returns keyboard input to the retained composer',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final otherWindowFocus = FocusNode();
      final otherDraft = TextEditingController();
      addTearDown(otherWindowFocus.dispose);
      addTearDown(otherDraft.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            focusRepositoryProvider.overrideWithValue(FakeFocusRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: otherWindowFocus,
                      controller: otherDraft,
                    ),
                  ),
                  Expanded(
                    child: GlobalQuickAddWindowApp(
                      onClose: () {},
                      onVoiceModeChanged: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      otherWindowFocus.requestFocus();
      await tester.pump();
      tester.testTextInput.enterText('Other window draft');
      await tester.pump();
      expect(otherWindowFocus.hasFocus, isTrue);
      final listener =
          tester.state(find.byKey(const Key('global-quick-add-focus')))
              as WindowListenerCallbacks;
      listener.onWindowFocus();
      await tester.pump();
      tester.testTextInput.enterText('Restored quick add');
      await tester.pump();
      expect(find.text('Restored quick add'), findsOneWidget);
      expect(otherDraft.text, 'Other window draft');
      expect(otherWindowFocus.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
  testWidgets('global voice window follows expansion and keeps composer text', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final recognizer = _IdleRecordedRecognizer();
    final voiceController = VoiceRecognitionController(
      recordedRecognizer: recognizer,
    );
    addTearDown(voiceController.dispose);
    final sizes = <bool>[];
    var closeCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          focusRepositoryProvider.overrideWithValue(FakeFocusRepository()),
          billingAccountEntitlementProvider.overrideWithValue(true),
          billingAccessProvider.overrideWithValue(
            AsyncData<BillingAccess>((
              hasActiveEntitlement: true,
              hasLocalStoreKitEntitlement: false,
              loading: false,
            )),
          ),
          applePurchasesSupportedProvider.overrideWithValue(false),
          voiceRecognitionControllerProvider.overrideWithValue(voiceController),
        ],
        child: GlobalQuickAddWindowApp(
          onClose: () => closeCount++,
          onVoiceModeChanged: sizes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sidebar-quick-add-input')),
      'Keep typed task',
    );
    await tester.tap(find.byKey(const Key('sidebar-quick-add-voice')));
    await tester.pumpAndSettle();
    expect(sizes, [true]);
    await tester.tap(find.byKey(const Key('voice-collapse')));
    await tester.pumpAndSettle();
    expect(sizes, [true, false]);
    await tester.tap(find.byKey(const Key('voice-expand')));
    await tester.pumpAndSettle();
    expect(sizes, [true, false, true]);
    expect(recognizer.cancelCalls, 0);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(sizes, [true, false, true, false]);
    expect(recognizer.cancelCalls, 1);
    expect(find.text('Keep typed task'), findsOneWidget);
    expect(closeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('global quick add window uses the shared Pomodoist composer', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var closeCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          focusRepositoryProvider.overrideWithValue(FakeFocusRepository()),
        ],
        child: GlobalQuickAddWindowApp(
          onClose: () => closeCount++,
          onVoiceModeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddComposer), findsOneWidget);
    expect(find.byKey(const Key('sidebar-quick-add-input')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('sidebar-quick-add-input')),
      'Global task tomorrow 10:00 p1',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(AppDateTimePicker),
            matching: find.byType(ShadButton),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change time'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker-offset-15')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar-quick-add-submit')));
    await tester.pumpAndSettle();

    final tasks = await db.select(db.tasks).get();
    expect(tasks.single.content, 'Global task');
    expect(tasks.single.priority, 1);
    final schedule = TaskSchedule.fromJsonString(tasks.single.dueJson)!;
    expect(schedule.start!.toLocal().hour, 10);
    expect(schedule.start!.toLocal().minute, 15);
    expect(closeCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });
}

class _IdleRecordedRecognizer extends RecordedVoiceRecognizer {
  int cancelCalls = 0;

  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    throw StateError('Opening the voice panel must not start recording.');
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) async {
    throw StateError('No recording was started.');
  }

  @override
  Future<void> cancel() async => cancelCalls++;
}
