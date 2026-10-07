import 'dart:async';
import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pomodoist/data/services/account/account_overview_service.dart';
import 'package:pomodoist/data/services/auth/account_profile_service.dart';
import 'package:pomodoist/data/services/account/account_management_service.dart';
import 'package:pomodoist/data/repositories/account/sdk_account_management_repository.dart';
import 'package:pomodoist/domain/models/account/avatar_emoji.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final emoji in [
    '😀',
    '❤️',
    '❤',
    '👍🏽',
    '🇷🇺',
    '👨‍👩‍👧‍👦',
    '1️⃣',
    '🫩',
  ]) {
    test('preserves the whole emoji $emoji', () {
      expect(normalizeAvatarEmoji(' $emoji '), emoji);
    });
  }
  for (final input in [
    '',
    ' ',
    'hello',
    'a',
    '1',
    '😀😃',
    '😀 text',
    '\u200d',
  ]) {
    test('rejects non-emoji avatar ${jsonEncode(input)}', () {
      expect(() => normalizeAvatarEmoji(input), throwsArgumentError);
    });
  }
  test('null explicitly resets the avatar', () {
    expect(normalizeAvatarEmoji(null), isNull);
  });

  group('profile transport', () {
    late SupabaseClient client;
    final requests = <http.Request>[];
    var currentId = 'user-a';
    var token = 'session-a';
    Future<http.Response> Function(http.Request)? respond;

    setUp(() {
      currentId = 'user-a';
      token = 'session-a';
      requests.clear();
      respond = null;
      client = SupabaseClient(
        'https://example.test',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.startsWith('/auth/')) {
            return http.Response(
              jsonEncode({
                'access_token': token,
                'refresh_token': 'refresh-$token',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': currentId,
                  'aud': 'authenticated',
                  'created_at': '2026-01-01T00:00:00Z',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          requests.add(request);
          return respond?.call(request) ??
              Future.value(
                http.Response(
                  '{"id":"user-a"}',
                  200,
                  headers: {'content-type': 'application/json'},
                  request: request,
                ),
              );
        }),
      );
    });
    tearDown(() => client.dispose());
    Future<void> signIn() async {
      await client.auth.signInWithPassword(
        email: 'a@example.test',
        password: 'pass',
      );
    }

    test('sends normalized emoji only to the signed-in profile', () async {
      await signIn();
      (await AccountProfileService(
        client,
      ).updateAvatarEmoji('user-a', ' 👍🏽 ')).getOrThrow();
      expect(requests.single.method, 'PATCH');
      expect(requests.single.url.queryParameters['id'], 'eq.user-a');
      expect(jsonDecode(requests.single.body), {'avatar_emoji': '👍🏽'});
    });
    test('late deletion cleanup cannot sign out a different account', () async {
      await signIn();
      final repository = SdkAccountManagementRepository(
        service: AccountManagementService(
          AccountClient.fromSupabaseClient(client),
        ),
        userId: 'deleted-account',
        timeout: const Duration(seconds: 1),
        profile: () => null,
      );
      (await repository.signOut()).getOrThrow();
      expect(client.auth.currentUser?.id, 'user-a');
    });
    test('sends SQL null on reset', () async {
      await signIn();
      (await AccountProfileService(
        client,
      ).updateAvatarEmoji('user-a', null)).getOrThrow();
      expect(jsonDecode(requests.single.body), {'avatar_emoji': null});
    });
    test(
      'a repository captured for another account cannot save an avatar',
      () async {
        await signIn();
        final repository = SdkAccountManagementRepository(
          service: AccountManagementService(
            AccountClient.fromSupabaseClient(client),
          ),
          userId: 'user-b',
          timeout: const Duration(seconds: 1),
          profile: () => AccountProfileService(client),
        );
        await expectLater(
          repository.updateAvatarEmoji('😀').then((r) => r.getOrThrow()),
          throwsStateError,
        );
        expect(requests, isEmpty);
      },
    );
    test(
      'rejects signed-out, wrong-account and invalid-input writes',
      () async {
        final service = AccountProfileService(client);
        await expectLater(
          service.updateAvatarEmoji('user-a', '😀').then((r) => r.getOrThrow()),
          throwsStateError,
        );
        await signIn();
        await expectLater(
          service.updateAvatarEmoji('user-b', '😀').then((r) => r.getOrThrow()),
          throwsStateError,
        );
        await expectLater(
          service
              .updateAvatarEmoji('user-a', '😀😀')
              .then((r) => r.getOrThrow()),
          throwsArgumentError,
        );
        expect(requests, isEmpty);
      },
    );
    test('reports network failure and permits retry', () async {
      await signIn();
      respond = (_) async => throw http.ClientException('Offline');
      final service = AccountProfileService(client);
      await expectLater(
        service.updateAvatarEmoji('user-a', '😀').then((r) => r.getOrThrow()),
        throwsA(isA<http.ClientException>()),
      );
      respond = null;
      (await service.updateAvatarEmoji('user-a', '😀')).getOrThrow();
      expect(requests.length, 2);
    });
    test('does not publish success to a replacement session', () async {
      await signIn();
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      respond = (_) {
        started.complete();
        return pending.future;
      };
      final save = AccountProfileService(
        client,
      ).updateAvatarEmoji('user-a', '😀');
      await started.future;
      token = 'session-b';
      await signIn();
      pending.complete(
        http.Response(
          '{"id":"user-a"}',
          200,
          headers: {'content-type': 'application/json'},
          request: requests.single,
        ),
      );
      await expectLater(save.then((r) => r.getOrThrow()), throwsStateError);
      expect(client.auth.currentSession?.accessToken, 'session-b');
    });
    for (final emoji in <String?>['👨‍👩‍👧‍👦', null]) {
      test('loads an overview with avatar $emoji', () async {
        await signIn();
        respond = (request) async => http.Response(
          jsonEncode({
            'profile': {
              'id': 'user-a',
              'displayName': 'User',
              'pomodoistIsPro': true,
              'avatarEmoji': ?emoji,
            },
            'apps': [],
            'generatedAt': '2026-10-04T00:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
        final overview = await AccountOverviewService(
          AccountClient.fromSupabaseClient(client),
          client: client,
        ).load();
        expect(overview.profile.avatarEmoji, emoji);
        expect(overview.profile.displayName, 'User');
        expect(overview.profile.isPro, isTrue);
        expect(requests.single.url.path, '/rest/v1/rpc/get_account_overview');
      });
    }
    for (final malformed in <Object>['words', '😀😀', 42]) {
      test(
        'malformed avatar $malformed does not break account loading',
        () async {
          await signIn();
          respond = (request) async => http.Response(
            jsonEncode({
              'profile': {
                'id': 'user-a',
                'avatarEmoji': malformed,
                'pomodoistIsPro': true,
              },
              'apps': [],
              'generatedAt': '2026-10-04T00:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
          final overview = await AccountOverviewService(
            AccountClient.fromSupabaseClient(client),
            client: client,
          ).load();
          expect(overview.profile.avatarEmoji, isNull);
          expect(overview.profile.isPro, isTrue);
        },
      );
    }
  });
}
