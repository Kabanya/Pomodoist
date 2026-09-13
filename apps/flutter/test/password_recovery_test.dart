import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pomodoist/app/account_auth_feedback.dart';
import 'package:pomodoist/app/password_recovery.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'same-user session replacement revokes permission before asynchronous events run',
    () async {
      final fixture = _Fixture(attach: false);
      addTearDown(fixture.dispose);
      bool? allowedDuringSignIn;
      final sub = fixture.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.signedIn) {
          allowedDuringSignIn = fixture.recovery.canSave;
        }
      });
      fixture.recovery.attach(fixture.auth);
      await fixture.recover();
      await fixture.signIn();
      expect(allowedDuringSignIn, isFalse);
      await sub.cancel();
    },
  );

  test(
    'late password response never replaces a different signed-in account',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.recover();
      final originalResponse = fixture.userResponse();
      final pending = Completer<http.Response>();
      fixture.updateResponse = () => pending.future;
      final save = fixture.recovery.savePassword('new', 'new');
      await pumpEventQueue();
      fixture.recovery.dismiss();
      fixture.userId = 'another-person';
      await fixture.signIn();
      pending.complete(originalResponse);
      expect(await save, isFalse);
      expect(fixture.auth.currentUser?.id, 'another-person');
      expect(fixture.auth.currentSession?.accessToken, fixture.token('normal'));
    },
  );

  test(
    'PKCE recovery verifies the exchanged code and replays at cold attachment',
    () async {
      final fixture = _Fixture(attach: false, pkce: true);
      addTearDown(fixture.dispose);
      fixture.recovery.attach(fixture.auth);
      expect(
        await fixture.recovery.requestEmail(
          'person@example.com',
          redirectTo: 'pomodoist://login-callback?returnTo=%2Freset-password',
        ),
        isTrue,
      );
      expect(fixture.emails.single.$1['code_challenge'], isNotEmpty);
      expect(fixture.emails.single.$1['code_challenge_method'], 's256');
      fixture.recovery.attach(null);
      await fixture.auth.getSessionFromUrl(
        Uri.parse('pomodoist://login-callback?code=verified-code'),
      );
      fixture.recovery.attach(fixture.auth);
      await pumpEventQueue();
      expect(fixture.recovery.canSave, isTrue);
      expect(
        await fixture.recovery.savePassword('new password', 'new password'),
        isTrue,
      );
    },
  );

  test('a callback that never verifies leaves a usable invalid-link state', () {
    fakeAsync((async) {
      final controller = PasswordRecoveryController();
      controller.beginCallback();
      expect(controller.stage, PasswordRecoveryStage.checking);
      expect(controller.canSave, isFalse);
      async.elapse(const Duration(seconds: 16));
      expect(controller.stage, PasswordRecoveryStage.invalid);
      expect(controller.failure?.recovery, AccountAuthRecovery.sendNewLink);
      controller.dispose();
    });
  });

  test(
    'a stalled save allows leaving without allowing another concurrent update',
    () {
      fakeAsync((async) {
        final fixture = _Fixture();
        unawaited(fixture.recover());
        async.elapse(Duration.zero);
        expect(fixture.recovery.canSave, isTrue);
        final pending = Completer<http.Response>();
        fixture.updateResponse = () => pending.future;
        unawaited(fixture.recovery.savePassword('first', 'first'));
        async.flushMicrotasks();
        expect(fixture.recovery.updating, isTrue);
        async.elapse(const Duration(seconds: 31));
        expect(fixture.recovery.takingLonger, isTrue);
        fixture.recovery.dismiss();
        expect(fixture.recovery.needsRoute, isFalse);
        unawaited(fixture.recover(tokenId: 'new-recovery'));
        async.elapse(Duration.zero);
        unawaited(fixture.recovery.savePassword('second', 'second'));
        async.flushMicrotasks();
        expect(fixture.updates, ['first']);
        pending.complete(fixture.userResponse());
        async.flushMicrotasks();
        expect(fixture.recovery.canSave, isTrue);
        expect(fixture.recovery.stage, PasswordRecoveryStage.ready);
        unawaited(fixture.dispose());
        async.flushMicrotasks();
      });
    },
  );

  test(
    'ordinary sessions and URL intent cannot authorize password changes',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.signIn();
      fixture.recovery.beginCallback();
      expect(fixture.recovery.canSave, isFalse);
      expect(
        await fixture.recovery.savePassword('new password', 'new password'),
        isFalse,
      );
      expect(fixture.updates, isEmpty);
    },
  );

  test(
    'a recovery event received before the controller attaches survives cold startup',
    () async {
      final fixture = _Fixture(attach: false);
      addTearDown(fixture.dispose);
      await fixture.recover();
      fixture.recovery.attach(fixture.auth);
      await pumpEventQueue();
      expect(fixture.recovery.canSave, isTrue);
      expect(
        await fixture.recovery.savePassword(' new password ', ' new password '),
        isTrue,
      );
      expect(fixture.updates, [' new password ']);
      expect(
        fixture.updateRequests.single.url.toString(),
        'https://account.test/auth/v1/user',
      );
      expect(
        fixture.updateRequests.single.headers['authorization'],
        'Bearer ${fixture.token('recovery')}',
      );
      expect(
        fixture.updateRequests.single.headers['content-type'],
        'application/json',
      );
      expect(fixture.updateRequests.single.headers['apikey'], 'public-key');
      expect(fixture.recovery.stage, PasswordRecoveryStage.updated);
      expect(fixture.auth.currentUser?.id, 'person');
    },
  );

  test('empty and mismatched passwords never reach the server', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.recover();
    expect(await fixture.recovery.savePassword('', ''), isFalse);
    expect(
      fixture.recovery.failure?.kind,
      AccountAuthFailureKind.passwordRequired,
    );
    expect(await fixture.recovery.savePassword('first', 'second'), isFalse);
    expect(
      fixture.recovery.failure?.kind,
      AccountAuthFailureKind.passwordMismatch,
    );
    expect(fixture.updates, isEmpty);
    expect(fixture.recovery.canSave, isTrue);
  });

  test(
    'saving blocks repeated requests and consumes recovery only after success',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.recover();
      final pending = Completer<http.Response>();
      fixture.updateResponse = () => pending.future;
      final save = fixture.recovery.savePassword('new', 'new');
      expect(await fixture.recovery.savePassword('other', 'other'), isFalse);
      await pumpEventQueue();
      expect(fixture.updates, ['new']);
      pending.complete(fixture.userResponse());
      expect(await save, isTrue);
      expect(await fixture.recovery.savePassword('again', 'again'), isFalse);
      expect(fixture.updates, ['new']);
      await fixture.recover();
      expect(
        fixture.recovery.canSave,
        isFalse,
        reason: 'Duplicate recovery links cannot reopen a consumed form',
      );
    },
  );

  test(
    'network and password errors keep recovery available for retry',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.recover();
      fixture.updateResponse = () async => http.Response(
        jsonEncode({'error_code': 'weak_password', 'msg': 'private detail'}),
        422,
      );
      expect(await fixture.recovery.savePassword('short', 'short'), isFalse);
      expect(
        fixture.recovery.failure?.kind,
        AccountAuthFailureKind.weakPassword,
      );
      expect(fixture.recovery.canSave, isTrue);
      fixture.updateResponse = () async =>
          throw http.ClientException('private network detail');
      expect(await fixture.recovery.savePassword('longer', 'longer'), isFalse);
      expect(fixture.recovery.canSave, isTrue);
      fixture.updateResponse = fixture.userResponse;
      expect(await fixture.recovery.savePassword('longer', 'longer'), isTrue);
    },
  );

  test(
    'signing in normally invalidates recovery even for the same user',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.recover();
      await fixture.signIn();
      expect(fixture.recovery.canSave, isFalse);
      expect(await fixture.recovery.savePassword('new', 'new'), isFalse);
      expect(fixture.updates, isEmpty);
    },
  );

  test(
    'late save completion cannot restore recovery after leaving the flow',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.recover();
      final pending = Completer<http.Response>();
      fixture.updateResponse = () => pending.future;
      final save = fixture.recovery.savePassword('new', 'new');
      await pumpEventQueue();
      fixture.recovery.dismiss();
      pending.complete(fixture.userResponse());
      expect(await save, isFalse);
      expect(fixture.recovery.stage, PasswordRecoveryStage.idle);
    },
  );

  test('a new verified recovery can start after a consumed recovery', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.recover();
    expect(await fixture.recovery.savePassword('new', 'new'), isTrue);
    await fixture.recover(tokenId: 'different-session');
    expect(fixture.recovery.canSave, isTrue);
  });

  test(
    'recovery email preserves redirect and CAPTCHA and rejects duplicate sends',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final pending = Completer<http.Response>();
      fixture.emailResponse = () => pending.future;
      final send = fixture.recovery.requestEmail(
        ' person@example.com ',
        redirectTo: 'pomodoist://login-callback?returnTo=%2Freset-password',
        captchaToken: 'verified',
      );
      expect(
        await fixture.recovery.requestEmail(
          'other@example.com',
          redirectTo: 'ignored',
        ),
        isFalse,
      );
      await pumpEventQueue();
      expect(fixture.emails.single.$1, {
        'email': 'person@example.com',
        'gotrue_meta_security': {'captcha_token': 'verified'},
        'code_challenge': null,
        'code_challenge_method': null,
      });
      expect(
        fixture.emails.single.$2,
        'pomodoist://login-callback?returnTo=%2Freset-password',
      );
      pending.complete(http.Response('{}', 200));
      expect(await send, isTrue);
      expect(fixture.recovery.canSave, isFalse);
    },
  );

  test(
    'email validation, rate limits, and neutral unknown-account response',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      expect(
        await fixture.recovery.requestEmail('invalid', redirectTo: 'callback'),
        isFalse,
      );
      expect(fixture.emails, isEmpty);
      fixture.emailResponse = () async => http.Response(
        jsonEncode({
          'error_code': 'over_email_send_rate_limit',
          'msg': 'private detail',
        }),
        429,
      );
      expect(
        await fixture.recovery.requestEmail(
          'person@example.com',
          redirectTo: 'callback',
        ),
        isFalse,
      );
      expect(
        fixture.recovery.failure?.kind,
        AccountAuthFailureKind.emailRateLimited,
      );
      fixture.emailResponse = () async => http.Response(
        jsonEncode({'error_code': 'user_not_found', 'msg': 'private detail'}),
        400,
      );
      expect(
        await fixture.recovery.requestEmail(
          'unknown@example.com',
          redirectTo: 'callback',
        ),
        isTrue,
      );
      expect(fixture.recovery.failure, isNull);
    },
  );

  test(
    'failed callback is recoverable and never accepts a current ordinary session',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.signIn();
      fixture.recovery.beginCallback(
        failure: const AccountAuthFailure(
          AccountAuthFailureKind.linkExpired,
          field: AccountAuthField.form,
          recovery: AccountAuthRecovery.sendNewLink,
        ),
      );
      expect(fixture.recovery.stage, PasswordRecoveryStage.invalid);
      expect(fixture.recovery.canSave, isFalse);
      expect(
        fixture.recovery.failure?.kind,
        AccountAuthFailureKind.linkExpired,
      );
    },
  );
}

class _Fixture {
  _Fixture({bool attach = true, bool pkce = false}) {
    final client = MockClient((request) async {
      if (request.method == 'PUT') {
        updateRequests.add(request);
        updates.add((jsonDecode(request.body) as Map)['password'] as String);
        return updateResponse?.call() ?? userResponse();
      }
      if (request.url.path.endsWith('/recover')) {
        emails.add((
          jsonDecode(request.body) as Map<String, dynamic>,
          request.url.queryParameters['redirect_to'],
        ));
        return emailResponse?.call() ?? http.Response('{}', 200);
      }
      if (request.url.path.endsWith('/token')) {
        return http.Response(jsonEncode(session()), 200);
      }
      return userResponse();
    });
    auth = GoTrueClient(
      url: 'https://account.test/auth/v1',
      headers: {'apikey': 'public-key'},
      flowType: pkce ? AuthFlowType.pkce : AuthFlowType.implicit,
      asyncStorage: _Storage(),
      autoRefreshToken: false,
      httpClient: client,
    );
    recovery = PasswordRecoveryController(
      userEndpoint: Uri.parse('https://account.test/auth/v1/user'),
      httpClient: client,
    );
    if (attach) recovery.attach(auth);
  }
  late final GoTrueClient auth;
  late final PasswordRecoveryController recovery;
  final updates = <String>[];
  final updateRequests = <http.Request>[];
  final emails = <(Map<String, dynamic>, String?)>[];
  FutureOr<http.Response> Function()? updateResponse;
  Future<http.Response> Function()? emailResponse;
  String userId = 'person';
  Map<String, dynamic> get user => {
    'id': userId,
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'aud': 'authenticated',
    'created_at': '2026-09-10T00:00:00Z',
    'email': 'person@example.com',
  };
  String token(String id) {
    String part(Object v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({'sub': userId, 'session_id': id, 'exp': 2100000000})}.signature';
  }

  Map<String, dynamic> session() => {
    'access_token': token('normal'),
    'refresh_token': 'refresh',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': user,
  };
  http.Response userResponse() => http.Response(jsonEncode(user), 200);
  Future<void> recover({String tokenId = 'recovery'}) async {
    await auth.getSessionFromUrl(
      Uri.parse('pomodoist://login-callback').replace(
        fragment: Uri(
          queryParameters: {
            'access_token': token(tokenId),
            'refresh_token': 'refresh',
            'expires_in': '3600',
            'token_type': 'bearer',
            'type': 'recovery',
          },
        ).query,
      ),
    );
    await pumpEventQueue();
  }

  Future<void> signIn() async {
    await auth.signInWithPassword(email: 'person@example.com', password: 'old');
    await pumpEventQueue();
  }

  Future<void> dispose() async {
    recovery.dispose();
    auth.dispose();
  }
}

class _Storage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}
