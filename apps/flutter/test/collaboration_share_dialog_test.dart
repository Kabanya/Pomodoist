import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/config/account_providers.dart';
import 'package:pomodoist/app/config/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/collaboration/presentation/collaboration_providers.dart';
import 'package:pomodoist/features/collaboration/presentation/share_project_dialog.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

import 'support/test_app.dart';

const _projectId = 'project-1';
const _actor = 'user-1';

ProjectItem _project() => ProjectItem(
  id: _projectId,
  userId: _actor,
  name: 'Shared project',
  orderKey: 'a',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _SignedInAccount implements AccountClient {
  @override
  String? get currentUserId => _actor;

  @override
  Stream<AccountAuthState> accountAuthStateChanges() =>
      const Stream<AccountAuthState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpShareDialog(
  WidgetTester tester, {
  AccountClient? account,
  bool withoutRepository = false,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        accountClientProvider.overrideWithValue(account),
        if (withoutRepository)
          collaborationRepositoryProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        builder: testAppBuilder,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('open-share'),
                onPressed: () => showShareProjectDialog(context, _project()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-share')));
  await tester.pumpAndSettle();
}

Future<void> _drainSnackBarsAndDispose(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  setUpAll(loadTestAppResources);

  testWidgets('asks to sign in when the share button has no session', (
    tester,
  ) async {
    await _pumpShareDialog(tester);
    expect(find.byKey(const Key('collaboration-share-start')), findsOne);

    await tester.tap(find.byKey(const Key('collaboration-share-start')));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.collaborationSignedOut), findsOne);
    expect(find.text(l10n.collaborationUnavailable), findsNothing);
    expect(find.byKey(const Key('collaboration-share-start')), findsOne);
    await _drainSnackBarsAndDispose(tester);
  });

  testWidgets(
    'reports unavailability when the signed-in user has no repository',
    (tester) async {
      await _pumpShareDialog(
        tester,
        account: _SignedInAccount(),
        withoutRepository: true,
      );

      await tester.tap(find.byKey(const Key('collaboration-share-start')));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.collaborationUnavailable), findsOne);
      expect(find.text(l10n.collaborationSignedOut), findsNothing);
      await _drainSnackBarsAndDispose(tester);
    },
  );
}
