import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/global_quick_add_window.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/quick_add_bar.dart';

void main() {
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
