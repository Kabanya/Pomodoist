import 'dart:async';
import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/collaboration/widgets/public_project_screen.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';

import 'support/test_app.dart';

final _token = List.filled(64, 'a').join();

/// A visitor without a session; the public link must not require one.
class _AnonymousAccount implements AccountClient {
  _AnonymousAccount(this.respond);

  final Future<AccountFunctionResponse> Function(Map<String, dynamic> body)
  respond;
  final calls = <Map<String, dynamic>>[];

  @override
  String? get currentUserId => null;

  @override
  Future<AccountFunctionResponse> invokeFunction(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    String? region,
  }) {
    final arguments = Map<String, dynamic>.from(body! as Map);
    calls.add({'function': functionName, ...arguments});
    return respond(arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _projection({
  List<Map<String, dynamic>>? projects,
  List<Map<String, dynamic>>? tasks,
  List<Map<String, dynamic>>? comments,
}) => {
  'scope': {'id': 'scope-1', 'rootProjectId': 'project-1'},
  'projects':
      projects ??
      [
        {'id': 'project-1', 'name': 'Launch plan'},
      ],
  'tasks':
      tasks ??
      [
        {
          'id': 'task-1',
          'content': 'Write the brief',
          'projectId': 'project-1',
          'status': 'open',
          'orderKey': 'a',
        },
      ],
  'comments': comments ?? const [],
};

Map<String, dynamic> _task({
  required String id,
  required String content,
  String projectId = 'project-1',
  String? parentId,
  String status = 'open',
  String? creatorName,
  List<String>? assigneeNames,
  String? dueJson,
}) => {
  'id': id,
  'content': content,
  'projectId': projectId,
  'parentId': ?parentId,
  'status': status,
  'orderKey': 'a',
  'creatorName': ?creatorName,
  'assigneeNames': ?assigneeNames,
  'dueJson': ?dueJson,
};

Map<String, dynamic> _comment({
  required String id,
  required String taskId,
  required String body,
  String? creatorName,
}) => {
  'id': id,
  'taskId': taskId,
  'body': body,
  'creatorName': ?creatorName,
  'createdAt': '2026-09-14T10:00:00Z',
};

double _indent(WidgetTester tester, String taskId) {
  final padding = tester
      .widget<Padding>(find.byKey(Key('public-project-task-$taskId')))
      .padding;
  return (padding as EdgeInsets).left;
}

Future<_AnonymousAccount> _pumpScreen(
  WidgetTester tester, {
  Future<AccountFunctionResponse> Function(Map<String, dynamic> body)? respond,
  String? token,
  bool settle = true,
  Size? surfaceSize,
}) async {
  if (surfaceSize != null) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = surfaceSize;
    addTearDown(tester.view.reset);
  }
  final account = _AnonymousAccount(
    respond ??
        (_) async => AccountFunctionResponse(status: 200, data: _projection()),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [accountClientProvider.overrideWithValue(account)],
      child: MaterialApp(
        builder: testAppBuilder,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PublicProjectScreen(token: token ?? _token),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
  return account;
}

void main() {
  setUpAll(loadTestAppResources);

  testWidgets('renders the shared project with its tasks and comments', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pumpScreen(
      tester,
      respond: (_) async => AccountFunctionResponse(
        status: 200,
        data: _projection(
          tasks: [
            _task(
              id: 'task-1',
              content: 'Write the brief',
              creatorName: 'Dana',
              assigneeNames: const ['Alice'],
              dueJson: jsonEncode({'type': 'allDay', 'date': '2026-09-20'}),
            ),
            _task(
              id: 'task-2',
              content: 'Review the brief',
              parentId: 'task-1',
              status: 'completed',
            ),
          ],
          comments: [
            _comment(
              id: 'comment-1',
              taskId: 'task-1',
              body: 'Looks good',
              creatorName: 'Bob',
            ),
          ],
        ),
      ),
    );

    expect(find.byKey(const Key('public-project-title')), findsOneWidget);
    expect(find.text('Launch plan'), findsOneWidget);
    expect(find.text(l10n.collaborationSharedBadge), findsOneWidget);
    expect(find.text(l10n.collaborationPublicNotice), findsOneWidget);
    expect(find.text(l10n.collaborationPublicTasks), findsOneWidget);
    expect(find.text('Write the brief'), findsOneWidget);
    expect(find.text('Review the brief'), findsOneWidget);
    expect(find.text(l10n.taskTimeStatusCompleted), findsOneWidget);
    expect(find.text('Dana'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text(l10n.collaborationComments), findsOneWidget);
    expect(find.text('Looks good'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byKey(const Key('public-project-open')), findsOneWidget);
    expect(find.byKey(const Key('public-project-loading')), findsNothing);
    expect(find.byKey(const Key('public-project-empty')), findsNothing);
  });

  testWidgets('loads the projection anonymously with the exact token', (
    tester,
  ) async {
    final account = await _pumpScreen(tester);

    expect(account.currentUserId, isNull);
    expect(account.calls, hasLength(1));
    expect(account.calls.single['function'], 'pomodoist-collaboration');
    expect(account.calls.single['action'], 'publicRead');
    expect(account.calls.single['token'], _token);
    expect(find.text('Launch plan'), findsOneWidget);
  });

  testWidgets('reports a revoked link as unavailable', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pumpScreen(
      tester,
      respond: (_) async => AccountFunctionResponse(
        status: 403,
        data: {'error': 'Link revoked', 'code': '42501'},
      ),
    );

    expect(find.text(l10n.collaborationPublicUnavailable), findsOneWidget);
    expect(find.text(l10n.collaborationError), findsNothing);
    expect(find.byKey(const Key('public-project-retry')), findsNothing);
  });

  testWidgets('rejects a malformed token without calling the server', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    for (final token in [
      '',
      'not-a-token',
      List.filled(63, 'a').join(),
      '${List.filled(63, 'a').join()}z',
    ]) {
      final account = await _pumpScreen(tester, token: token);

      expect(account.calls, isEmpty, reason: 'token "$token"');
      expect(find.text(l10n.collaborationPublicUnavailable), findsOneWidget);
      expect(find.byKey(const Key('public-project-open')), findsOneWidget);
    }
  });

  testWidgets('shows the empty state for an empty projection', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pumpScreen(
      tester,
      respond: (_) async => AccountFunctionResponse(
        status: 200,
        data: _projection(
          projects: const [],
          tasks: const [],
          comments: const [],
        ),
      ),
    );

    expect(find.text(l10n.collaborationPublicEmpty), findsOneWidget);
    expect(find.byKey(const Key('public-project-empty')), findsOneWidget);
    expect(find.text(l10n.collaborationPublicNotice), findsNothing);
  });

  testWidgets('retries a failed request', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    var attempts = 0;
    final account = await _pumpScreen(
      tester,
      respond: (_) async {
        attempts += 1;
        if (attempts == 1) {
          return AccountFunctionResponse(
            status: 503,
            data: {'error': 'Service unavailable', 'code': 'unavailable'},
          );
        }
        return AccountFunctionResponse(status: 200, data: _projection());
      },
    );

    expect(find.text(l10n.collaborationError), findsOneWidget);
    expect(find.text(l10n.collaborationPublicUnavailable), findsNothing);

    await tester.tap(find.byKey(const Key('public-project-retry')));
    await tester.pumpAndSettle();

    expect(account.calls, hasLength(2));
    expect(find.text(l10n.collaborationError), findsNothing);
    expect(find.text('Launch plan'), findsOneWidget);
  });

  testWidgets('shows a centred loading indicator while the link loads', (
    tester,
  ) async {
    final gate = Completer<AccountFunctionResponse>();
    await _pumpScreen(tester, respond: (_) => gate.future, settle: false);

    expect(find.byKey(const Key('public-project-loading')), findsOneWidget);

    gate.complete(AccountFunctionResponse(status: 200, data: _projection()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('public-project-loading')), findsNothing);
    expect(find.text('Launch plan'), findsOneWidget);
  });

  testWidgets('groups tasks by project and caps subtask indentation', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      surfaceSize: const Size(1400, 2400),
      respond: (_) async => AccountFunctionResponse(
        status: 200,
        data: _projection(
          projects: const [
            {'id': 'project-1', 'name': 'Launch plan'},
            {'id': 'project-2', 'name': 'Beta feedback'},
          ],
          tasks: [
            _task(id: 'p1', content: 'Write the brief'),
            _task(id: 'p1-sub', content: 'Add outline', parentId: 'p1'),
            _task(id: 'p1-sub-2', content: 'Add detail', parentId: 'p1-sub'),
            _task(id: 'p1-sub-3', content: 'Add numbers', parentId: 'p1-sub-2'),
            _task(id: 'p1-sub-4', content: 'Add charts', parentId: 'p1-sub-3'),
            _task(id: 'p1-sub-5', content: 'Add annex', parentId: 'p1-sub-4'),
            _task(id: 'p2', content: 'Collect notes', projectId: 'project-2'),
          ],
        ),
      ),
    );

    expect(find.text('Launch plan'), findsOneWidget);
    expect(find.text('Beta feedback'), findsOneWidget);
    expect(find.text('Add annex'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Add annex')).dy,
      lessThan(tester.getTopLeft(find.text('Collect notes')).dy),
    );
    expect(_indent(tester, 'p1'), 0);
    expect(_indent(tester, 'p1-sub'), 12);
    expect(_indent(tester, 'p1-sub-2'), 24);
    expect(_indent(tester, 'p1-sub-5'), 48);
  });
}
