import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pomodoist/app/account_auth_feedback.dart';
import 'package:pomodoist/app/email_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late GoTrueClient auth;
  late EmailAuthController controller;
  late Future<http.Response> Function(http.Request) respond;
  late List<http.Request> requests;
  setUp(() {
    requests = [];
    respond = (_) async => http.Response('{}', 200);
    auth = GoTrueClient(
      url: 'https://example.test/auth/v1',
      autoRefreshToken: false,
      asyncStorage: _Storage(),
      httpClient: MockClient((request) {
        requests.add(request);
        return respond(request);
      }),
    );
    controller = EmailAuthController(auth);
  });
  tearDown(() => auth.dispose());

  Future<EmailAuthResult?> submit(
    EmailAuthAction action, {
    String email = ' person@example.com ',
    String password = ' password with spaces ',
  }) => controller.submit(
    action: action,
    email: email,
    password: password,
    redirectTo: 'pomodoist://login-callback?returnTo=%2Ftoday',
    captchaToken: 'solved-captcha',
  );

  test(
    'validation and unavailable auth do not start network requests',
    () async {
      await expectLater(
        submit(EmailAuthAction.signIn, email: ''),
        throwsA(isA<AccountAuthFailure>()),
      );
      await expectLater(
        submit(EmailAuthAction.signUp, password: ''),
        throwsA(isA<AccountAuthFailure>()),
      );
      controller = EmailAuthController(null);
      await expectLater(
        submit(EmailAuthAction.signIn),
        throwsA(isA<AccountAuthFailure>()),
      );
      expect(requests, isEmpty);
    },
  );

  test(
    'new signup and masked duplicate both use a neutral check-email step',
    () async {
      for (final identities in [null, <Object>[]]) {
        respond = (_) async => http.Response(
          jsonEncode({
            'id': 'user',
            'aud': 'authenticated',
            'created_at': '2026-09-10T00:00:00Z',
            'email': 'person@example.com',
            'identities': ?identities,
          }),
          200,
        );
        expect(
          await submit(EmailAuthAction.signUp),
          EmailAuthResult.checkEmail,
        );
        expect(auth.currentSession, isNull);
      }
      final body = jsonDecode(requests.first.body) as Map;
      expect(body['email'], 'person@example.com');
      expect(body['password'], ' password with spaces ');
      expect(body['gotrue_meta_security']['captcha_token'], 'solved-captcha');
      expect(
        requests.first.url.queryParameters['redirect_to'],
        'pomodoist://login-callback?returnTo=%2Ftoday',
      );
    },
  );

  test(
    'password login and auto-confirm signup require an actual session',
    () async {
      final user = {
        'id': 'user',
        'aud': 'authenticated',
        'created_at': '2026-09-10T00:00:00Z',
      };
      respond = (_) async => http.Response(
        jsonEncode({
          'access_token': 'test-token',
          'refresh_token': 'refresh',
          'expires_in': 3600,
          'token_type': 'bearer',
          'user': user,
        }),
        200,
      );
      expect(await submit(EmailAuthAction.signIn), EmailAuthResult.signedIn);
      expect(await submit(EmailAuthAction.signUp), EmailAuthResult.signedIn);
      respond = (_) async => http.Response(jsonEncode({'user': user}), 200);
      await expectLater(
        submit(EmailAuthAction.signIn),
        throwsA(isA<AccountAuthFailure>()),
      );
    },
  );

  test('magic-link login never creates an unknown account', () async {
    expect(await submit(EmailAuthAction.magicLink), EmailAuthResult.checkEmail);
    final body = jsonDecode(requests.single.body) as Map;
    expect(requests.single.url.path, '/auth/v1/otp');
    expect(body['create_user'], isFalse);
    expect(body['gotrue_meta_security']['captcha_token'], 'solved-captcha');
    expect(body['code_challenge'], isNotEmpty);
  });

  test(
    'confirmation resends use signup resend with CAPTCHA and return path',
    () async {
      expect(
        await submit(EmailAuthAction.resendConfirmation, password: ''),
        EmailAuthResult.checkEmail,
      );
      final body = jsonDecode(requests.single.body) as Map;
      expect(requests.single.url.path, '/auth/v1/resend');
      expect(body['type'], 'signup');
      expect(body['gotrue_meta_security']['captcha_token'], 'solved-captcha');
      expect(
        requests.single.url.queryParameters['redirect_to'],
        'pomodoist://login-callback?returnTo=%2Ftoday',
      );
      expect(body.containsKey('password'), isFalse);
    },
  );

  test(
    'a pending request blocks every second action and a failed request can retry',
    () async {
      final pending = Completer<http.Response>();
      respond = (_) => pending.future;
      final first = submit(EmailAuthAction.magicLink);
      expect(await submit(EmailAuthAction.signUp), isNull);
      expect(await submit(EmailAuthAction.resendConfirmation), isNull);
      pending.complete(
        http.Response(
          '{"error_code":"over_email_send_rate_limit","msg":"private"}',
          429,
        ),
      );
      await expectLater(first, throwsA(isA<AuthException>()));
      expect(requests, hasLength(1));
      respond = (_) async => http.Response('{}', 200);
      expect(
        await submit(EmailAuthAction.magicLink),
        EmailAuthResult.checkEmail,
      );
    },
  );

  test(
    'missing users get neutral link results while genuine delivery errors remain errors',
    () async {
      respond = (_) async =>
          http.Response('{"error_code":"user_not_found","msg":"private"}', 404);
      expect(
        await submit(EmailAuthAction.magicLink),
        EmailAuthResult.checkEmail,
      );
      expect(
        await submit(EmailAuthAction.resendConfirmation),
        EmailAuthResult.checkEmail,
      );
      await expectLater(
        submit(EmailAuthAction.signIn),
        throwsA(isA<AuthException>()),
      );
      respond = (_) async =>
          http.Response('{"error_code":"otp_disabled","msg":"private"}', 422);
      expect(
        await submit(EmailAuthAction.magicLink),
        EmailAuthResult.checkEmail,
      );
      respond = (_) async => http.Response(
        '{"error_code":"email_send_failed","msg":"private"}',
        500,
      );
      await expectLater(
        submit(EmailAuthAction.magicLink),
        throwsA(isA<AuthException>()),
      );
    },
  );
}

class _Storage extends GotrueAsyncStorage {
  final _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}
