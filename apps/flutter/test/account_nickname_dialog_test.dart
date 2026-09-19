import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pomodoist/data/services/auth/account_profile_service.dart';
import 'package:pomodoist/ui/settings/widgets/account_nickname_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/test_app.dart';

void main() {
  setUpAll(loadTestAppResources);

  testWidgets('validates, retains failed draft, and prevents duplicate saves', (
    tester,
  ) async {
    final saved = <String>[];
    var pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        builder: testAppBuilder,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AccountNicknameDialog(
                  nickname: 'Old name',
                  onSave: (name) {
                    saved.add(name);
                    return pending.future;
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final input = find.byType(EditableText);
    expect(tester.widget<EditableText>(input).controller.text, 'Old name');
    await tester.enterText(input, '   ');
    await tester.tap(find.byKey(const Key('account-nickname-save')));
    await tester.pumpAndSettle();
    expect(find.text('Name is required'), findsOneWidget);
    expect(saved, isEmpty);
    await tester.enterText(input, '  Новый ник  ');
    await tester.tap(find.byKey(const Key('account-nickname-save')));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(saved, ['Новый ник']);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AccountNicknameDialog), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(input).controller.text, '  Новый ник  ');
    expect(
      find.text('Could not save your nickname. Please try again.'),
      findsOneWidget,
    );
    pending = Completer<void>();
    await tester.tap(find.byKey(const Key('account-nickname-save')));
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AccountNicknameDialog), findsNothing);
    expect(saved, ['Новый ник', 'Новый ник']);
  });

  test(
    'updates only the signed-in profile and rejects invalid sessions',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.com',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.contains('/auth/')) {
            return http.Response(
              jsonEncode({
                'access_token': 'test-token',
                'refresh_token': 'refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': 'user-1',
                  'aud': 'authenticated',
                  'created_at': '2026-01-01T00:00:00Z',
                  'app_metadata': {},
                  'user_metadata': {},
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            '{"id":"user-1"}',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        AccountProfileService(
          client,
        ).updateNickname('user-1', 'Name').then((value) => value.getOrThrow()),
        throwsStateError,
      );
      await client.auth.signInWithPassword(
        email: 'a@example.com',
        password: 'password',
      );
      requests.clear();
      await expectLater(
        AccountProfileService(
          client,
        ).updateNickname('user-2', 'Name').then((value) => value.getOrThrow()),
        throwsStateError,
      );
      await expectLater(
        AccountProfileService(
          client,
        ).updateNickname('user-1', '   ').then((value) => value.getOrThrow()),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
      (await AccountProfileService(
        client,
      ).updateNickname('user-1', '  Новый ник  ')).getOrThrow();
      expect(requests.single.method, 'PATCH');
      expect(requests.single.url.path, '/rest/v1/profiles');
      expect(requests.single.url.queryParameters['id'], 'eq.user-1');
      expect(jsonDecode(requests.single.body), {'display_name': 'Новый ник'});
    },
  );
}
