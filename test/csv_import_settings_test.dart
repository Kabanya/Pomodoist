import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/settings/presentation/csv_task_import_card.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  test('CSV import support is limited to web and macOS', () {
    expect(
      isCsvTaskImportSupported(web: true, platform: TargetPlatform.windows),
      isTrue,
    );
    expect(
      isCsvTaskImportSupported(web: false, platform: TargetPlatform.macOS),
      isTrue,
    );
    expect(
      isCsvTaskImportSupported(web: false, platform: TargetPlatform.windows),
      isFalse,
    );
  });

  test('macOS configurations can read user-selected files', () {
    for (final name in [
      'DebugProfile.entitlements',
      'LocalDebug.entitlements',
      'Release.entitlements',
    ]) {
      expect(
        File('macos/Runner/$name').readAsStringSync(),
        contains('com.apple.security.files.user-selected.read-only'),
      );
    }
  });

  testWidgets('opens selectable human and agent guides', (tester) async {
    await _pumpCard(tester, const CsvTaskImportCard());

    await tester.tap(find.byKey(const Key('csv-import-human-guide')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('csv-import-guide-dialog')), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('content'), findsOneWidget);

    await tester.tap(find.byKey(const Key('csv-import-guide-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('csv-import-agent-guide')));
    await tester.pumpAndSettle();
    expect(find.textContaining('pomodoist_csv_v1'), findsOneWidget);
  });

  testWidgets('previews and imports a selected CSV file', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final file = XFile.fromData(
      utf8.encode('content,project,labels\nImported,Work,Urgent\n'),
      name: 'tasks.csv',
      mimeType: 'text/csv',
    );
    await _pumpCard(
      tester,
      CsvTaskImportCard(pickFile: () async => file),
      db: db,
    );

    await tester.tap(find.byKey(const Key('csv-import-select-file')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('csv-import-preview-dialog')),
    );
    expect(find.byKey(const Key('csv-import-preview-dialog')), findsOneWidget);
    expect(find.textContaining('Work'), findsOneWidget);

    await tester.tap(find.byKey(const Key('csv-import-confirm')));
    await tester.pumpAndSettle();
    expect((await db.select(db.tasks).get()).single.content, 'Imported');
  });
}

Future<void> _pumpCard(WidgetTester tester, Widget card, {AppDatabase? db}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [if (db != null) appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: card)),
      ),
    ),
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
