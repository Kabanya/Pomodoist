import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_api.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_repository.dart';
import 'package:pomodoist/features/collaboration/presentation/collaboration_join_screen.dart';
import 'package:pomodoist/features/collaboration/presentation/collaboration_providers.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

import 'support/test_app.dart';

const _scopeId = 'scope-1';
const _projectId = 'project-1';
final _token = List.filled(64, 'b').join();

class _Harness {
  _Harness(this.db, this.calls);

  final AppDatabase db;
  final List<Map<String, dynamic>> calls;

  Iterable<Map<String, dynamic>> callsFor(String action) =>
      calls.where((call) => call['action'] == action);
}

Map<String, dynamic> _scopeJson() => {
  'id': _scopeId,
  'rootProjectId': _projectId,
  'ownerId': 'owner-1',
  'role': 'member',
  'revision': 1,
  'historyUnlimited': true,
  'members': const [],
};

Map<String, dynamic> _invitation({String role = 'member'}) => {
  'id': 'inv-1',
  'scopeId': _scopeId,
  'role': role,
  'token': _token,
  'expiresAt': '2026-09-20T10:00:00Z',
};

Future<_Harness> _pumpJoinScreen(
  WidgetTester tester, {
  required String token,
  Future<Map<String, dynamic>> Function(
    String action,
    Map<String, dynamic> args,
  )?
  handler,
  bool withoutRepository = false,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final calls = <Map<String, dynamic>>[];
  final repository = CollaborationRepository(
    db: db,
    api: CollaborationApi((body) async {
      final action = body['action'] as String? ?? '';
      final args = Map<String, dynamic>.from(body)..remove('action');
      calls.add({'action': action, ...args});
      return handler == null
          ? <String, dynamic>{'ok': true}
          : handler(action, args);
    }),
    queue: DriftSyncQueueRepository(db),
    synchronize: () async {},
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        collaborationRepositoryProvider.overrideWithValue(
          withoutRepository ? null : repository,
        ),
      ],
      child: MaterialApp(
        builder: testAppBuilder,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CollaborationJoinScreen(token: token),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(db, calls);
}

void main() {
  setUpAll(loadTestAppResources);

  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('accepting the invitation opens the shared project', (
    tester,
  ) async {
    final harness = await _pumpJoinScreen(
      tester,
      token: _token,
      handler: (action, args) async => switch (action) {
        'state' => {
          'invitations': [_invitation(role: 'member')],
        },
        'accept' => {'scope': _scopeJson()},
        _ => {'ok': true},
      },
    );

    expect(find.text(l10n.collaborationJoinTitle), findsOne);
    expect(find.text(l10n.collaborationJoinRole), findsOne);
    expect(find.text(l10n.collaborationRoleMember), findsOne);

    await tester.tap(find.byKey(const Key('collaboration-join-accept')));
    await tester.pumpAndSettle();

    expect(harness.callsFor('accept'), hasLength(1));
    expect(harness.callsFor('accept').single['token'], _token);
    expect(find.text(l10n.collaborationInvitationAccepted), findsOne);
    expect(find.text(l10n.collaborationJoinOpenProject), findsOne);
    expect(find.byKey(const Key('collaboration-join-open')), findsOne);
    expect(find.byKey(const Key('collaboration-join-accept')), findsNothing);
  });

  testWidgets('shows progress while the acceptance is in flight', (
    tester,
  ) async {
    final gate = Completer<Map<String, dynamic>>();
    final harness = await _pumpJoinScreen(
      tester,
      token: _token,
      handler: (action, args) async => switch (action) {
        'state' => {
          'invitations': [_invitation()],
        },
        'accept' => gate.future,
        _ => {'ok': true},
      },
    );

    expect(find.byKey(const Key('collaboration-join-progress')), findsNothing);

    await tester.tap(find.byKey(const Key('collaboration-join-accept')));
    await tester.pump();

    expect(harness.callsFor('accept'), hasLength(1));
    expect(find.byKey(const Key('collaboration-join-progress')), findsOne);

    gate.complete({'scope': _scopeJson()});
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('collaboration-join-progress')), findsNothing);
    expect(find.text(l10n.collaborationInvitationAccepted), findsOne);
  });

  testWidgets(
    'a revoked invitation reports unavailability and stays retryable',
    (tester) async {
      final harness = await _pumpJoinScreen(
        tester,
        token: _token,
        handler: (action, args) async => switch (action) {
          'state' => {
            'invitations': [_invitation()],
          },
          'accept' => {
            'error': 'Invitation is not available for this account',
            'code': '42501',
          },
          _ => {'ok': true},
        },
      );

      await tester.tap(find.byKey(const Key('collaboration-join-accept')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.collaborationJoinUnavailable), findsOne);
      expect(find.byKey(const Key('collaboration-join-open')), findsNothing);
      expect(find.byKey(const Key('collaboration-join-accept')), findsOne);

      await tester.tap(find.byKey(const Key('collaboration-join-accept')));
      await tester.pumpAndSettle();

      expect(harness.callsFor('accept'), hasLength(2));
      expect(find.text(l10n.collaborationJoinUnavailable), findsOne);
    },
  );

  testWidgets('a signed-out visitor sees the sign-in message', (tester) async {
    await _pumpJoinScreen(tester, token: _token, withoutRepository: true);

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.collaborationSignedOut), findsOne);
    expect(find.byKey(const Key('collaboration-join-accept')), findsNothing);
  });

  testWidgets('an empty token reports an invalid link without a server call', (
    tester,
  ) async {
    final harness = await _pumpJoinScreen(tester, token: '');

    expect(find.text(l10n.collaborationJoinInvalid), findsOne);
    expect(find.byKey(const Key('collaboration-join-accept')), findsNothing);
    expect(harness.calls, isEmpty);
  });

  testWidgets(
    'a malformed token reports an invalid link without a server call',
    (tester) async {
      final harness = await _pumpJoinScreen(tester, token: 'not-a-token');

      expect(find.text(l10n.collaborationJoinInvalid), findsOne);
      expect(harness.calls, isEmpty);
    },
  );

  testWidgets('an unfindable invitation still offers the accept action', (
    tester,
  ) async {
    final harness = await _pumpJoinScreen(
      tester,
      token: _token,
      handler: (action, args) async => {'ok': true},
    );

    expect(find.text(l10n.collaborationJoinTitle), findsOne);
    expect(harness.callsFor('accept'), isEmpty);

    await tester.tap(find.byKey(const Key('collaboration-join-accept')));
    await tester.pumpAndSettle();

    expect(harness.callsFor('accept'), hasLength(1));
    expect(harness.callsFor('accept').single['token'], _token);
  });

  testWidgets('a failed session is reported as signed out', (tester) async {
    await _pumpJoinScreen(
      tester,
      token: _token,
      handler: (action, args) async => switch (action) {
        'state' => {
          'invitations': [_invitation()],
        },
        'accept' => {
          'error': 'Authentication required',
          'code': 'unauthenticated',
        },
        _ => {'ok': true},
      },
    );

    await tester.tap(find.byKey(const Key('collaboration-join-accept')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.collaborationSignedOut), findsOne);
    expect(find.text(l10n.commonRetry), findsOne);
  });

  testWidgets('a missing function is reported as unavailable', (tester) async {
    await _pumpJoinScreen(
      tester,
      token: _token,
      handler: (action, args) async => switch (action) {
        'state' => {
          'invitations': [_invitation()],
        },
        'accept' => {
          'error': 'Requested function was not found',
          'code': 'function_not_found',
        },
        _ => {'ok': true},
      },
    );

    await tester.tap(find.byKey(const Key('collaboration-join-accept')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.collaborationUnavailable), findsOne);
    expect(find.text(l10n.commonRetry), findsOne);
  });
}
