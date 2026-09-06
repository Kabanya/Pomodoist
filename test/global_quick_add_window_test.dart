import 'package:app_voice/app_voice.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/app/global_quick_add_window.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/quick_add_bar.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
          billingAccountEntitlementProvider.overrideWithValue(true),
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
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: GlobalQuickAddWindowApp(
          onClose: () => closeCount++,
          onVoiceModeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add task'), findsOneWidget);
    expect(find.byType(QuickAddComposer), findsOneWidget);
    expect(find.byKey(const Key('sidebar-quick-add-input')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('sidebar-quick-add-input')),
      'Global task tomorrow 10:00 p1',
    );
    await tester.tap(find.byKey(const Key('sidebar-quick-add-submit')));
    await tester.pumpAndSettle();

    final tasks = await db.select(db.tasks).get();
    expect(tasks.single.content, 'Global task');
    expect(tasks.single.priority, 1);
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
