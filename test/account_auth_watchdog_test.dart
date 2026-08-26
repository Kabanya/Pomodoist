import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/captcha_verification.dart';
import 'package:pomodoist/app/runtime_public_config.dart';
import 'package:pomodoist/features/settings/presentation/settings_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthApiException, AuthRetryableFetchException;

void main() {
  testWidgets('email auth dialog stays wide on compact screens', (
    tester,
  ) async {
    final previousSize = tester.view.physicalSize;
    final previousDevicePixelRatio = tester.view.devicePixelRatio;
    tester.view
      ..physicalSize = const Size(406, 600)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..physicalSize = previousSize
        ..devicePixelRatio = previousDevicePixelRatio;
    });
    await _pumpAuthScreen(tester, _PendingAccountClient(), const LoginScreen());

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('account-email-field'))).width,
      greaterThanOrEqualTo(300),
    );
  });

  testWidgets('email sign-up sends the solved CAPTCHA token', (tester) async {
    if (!kIsWeb) return;
    final account = _SuccessfulAccountClient();
    await _pumpAuthScreen(
      tester,
      account,
      const LoginScreen(),
      config: RuntimePublicConfig.fromBuildTimeValues(
        environment: 'local',
        release: 'test',
        webAppUrl: 'http://127.0.0.1:7358',
        supabaseUrl: '',
        supabaseAnonKey: '',
        turnstileSiteKey: 'configured-site-key',
        sentryDsn: '',
      ),
    );

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('account-auth-mode')),
        matching: find.text('Create account'),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('account-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password-field')),
      'password',
    );
    await tester.pump();

    final submit = find.widgetWithText(FilledButton, 'Create account');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    final verification = tester.widget<CaptchaVerification>(
      find.byType(CaptchaVerification),
    );
    expect(
      verification.controller.acceptSolved(
        'dialog-test-token',
        verification.controller.generation,
      ),
      isTrue,
    );
    verification.onChanged();
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(account.signUpCalls, 1);
    expect(account.signUpCaptchaToken, 'dialog-test-token');
  });

  testWidgets('email auth exposes current and new password autofill modes', (
    tester,
  ) async {
    final account = _PendingAccountClient();
    await _pumpAuthScreen(tester, account, const LoginScreen());

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('account-email-field')))
          .autofillHints,
      const [AutofillHints.username, AutofillHints.email],
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('account-password-field')))
          .autofillHints,
      const [AutofillHints.password],
    );

    await tester.enterText(
      find.byKey(const Key('account-password-field')),
      'existing-password',
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('account-auth-mode')),
        matching: find.text('Create account'),
      ),
    );
    await tester.pump();

    final password = tester.widget<TextField>(
      find.byKey(const Key('account-password-field')),
    );
    expect(password.controller?.text, isEmpty);
    expect(password.autofillHints, const [AutofillHints.newPassword]);
    expect(find.text('Send link'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
  });

  testWidgets('unconfirmed email asks the user to confirm it', (tester) async {
    await _pumpAuthScreen(
      tester,
      _UnconfirmedEmailAccountClient(),
      const LoginScreen(),
    );

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password-field')),
      'password',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(
      find.text(
        'Confirm your email using the link we sent, then sign in again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Authentication failed. Check your details and try again.'),
      findsNothing,
    );
  });

  testWidgets('registration validates email and password before calling auth', (
    tester,
  ) async {
    final account = _SuccessfulAccountClient();
    final router = _authRouter('/register');
    addTearDown(router.dispose);
    await _pumpAuthRouter(tester, account, router);

    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pump();
    expect(find.text('Enter your email.'), findsOneWidget);
    expect(account.signUpCalls, 0);

    await tester.enterText(
      find.byKey(const Key('register-email-field')),
      'not-an-email',
    );
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pump();
    expect(find.textContaining('name@example.com'), findsOneWidget);
    expect(account.signUpCalls, 0);

    await tester.enterText(
      find.byKey(const Key('register-email-field')),
      'user@example.com',
    );
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pump();
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(account.signUpCalls, 0);
  });

  testWidgets('invalid credentials never reveal whether the account exists', (
    tester,
  ) async {
    await _pumpAuthScreen(
      tester,
      _FailingEmailAccountClient(
        const AuthApiException(
          'SECRET server detail',
          code: 'invalid_credentials',
        ),
      ),
      const LoginScreen(),
    );

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password-field')),
      'wrong-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(
      find.text(
        'The email or password is incorrect. Check both and try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('not found'), findsNothing);
  });

  testWidgets('existing email uses privacy-safe copy and preserves returnTo', (
    tester,
  ) async {
    final router = _authRouter('/register?returnTo=/projects');
    addTearDown(router.dispose);
    await _pumpAuthRouter(
      tester,
      _FailingEmailAccountClient(
        const AuthApiException('already exists', code: 'email_exists'),
      ),
      router,
    );

    await tester.enterText(
      find.byKey(const Key('register-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password-field')),
      'password',
    );
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pump();

    expect(
      find.text(
        'Could not create the account. If you registered with this email before, sign in instead.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('already exists'), findsNothing);

    await tester.tap(find.byKey(const Key('register-auth-recovery')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with email'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('account-email-field')))
          .controller
          ?.text,
      'user@example.com',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('account-password-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/register?returnTo=/projects',
    );
  });

  for (final scenario in <(Object, String)>[
    (
      AuthRetryableFetchException(message: 'SECRET offline detail'),
      'Could not reach the account service. Check your internet connection and try again.',
    ),
    (
      const AuthApiException(
        'SECRET rate detail',
        code: 'over_request_rate_limit',
      ),
      'Too many attempts. Wait a few minutes and try again.',
    ),
  ]) {
    testWidgets('email sign-in presents ${scenario.$2}', (tester) async {
      await _pumpAuthScreen(
        tester,
        _FailingEmailAccountClient(scenario.$1),
        const LoginScreen(),
      );
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-email-field')),
        'user@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('account-password-field')),
        'password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.text(scenario.$2), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
    });
  }

  testWidgets('successful email sign-in commits the autofill context', (
    tester,
  ) async {
    final account = _PendingAccountClient();
    await _pumpAuthScreen(tester, account, const LoginScreen());
    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password-field')),
      'password',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tester.testTextInput.unregister();
    messenger.setMockMethodCallHandler(SystemChannels.textInput, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.textInput, null);
      tester.testTextInput.register();
    });

    account.signIn.complete();
    await tester.pumpAndSettle();

    expect(
      calls.where(
        (call) =>
            call.method == 'TextInput.finishAutofillContext' &&
            call.arguments == true,
      ),
      hasLength(1),
    );
  });

  testWidgets('standalone registration advertises new credentials', (
    tester,
  ) async {
    final account = _PendingAccountClient();
    await _pumpAuthScreen(tester, account, const RegisterScreen());

    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('register-email-field')))
          .autofillHints,
      const [AutofillHints.username, AutofillHints.email],
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('register-password-field')))
          .autofillHints,
      const [AutofillHints.newPassword],
    );
  });

  testWidgets('successful registration opens its local destination', (
    tester,
  ) async {
    final account = _SuccessfulAccountClient();
    final router = _authRouter('/register?returnTo=/projects');
    addTearDown(router.dispose);
    await _pumpAuthRouter(tester, account, router);

    await tester.enterText(
      find.byKey(const Key('register-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password-field')),
      'password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();

    expect(account.signUpCalls, 1);
    expect(account.currentUserId, 'user-id');
    expect(router.routeInformationProvider.value.uri.toString(), '/projects');
    expect(find.byKey(const Key('register-password-field')), findsNothing);
  });

  testWidgets('disposed web CAPTCHA callback is ignored', (tester) async {
    if (!kIsWeb) return;
    final account = _SuccessfulAccountClient();
    final router = _authRouter('/register?returnTo=/projects');
    addTearDown(router.dispose);
    await _pumpAuthRouter(
      tester,
      account,
      router,
      config: RuntimePublicConfig.fromBuildTimeValues(
        environment: 'local',
        release: 'test',
        webAppUrl: 'http://127.0.0.1:7358',
        supabaseUrl: '',
        supabaseAnonKey: '',
        turnstileSiteKey: 'configured-site-key',
        sentryDsn: '',
      ),
    );

    await tester.pump();
    final staleOnChanged = tester
        .widget<CaptchaVerification>(find.byType(CaptchaVerification))
        .onChanged;
    router.go('/projects');
    await tester.pumpAndSettle();
    staleOnChanged();

    expect(router.routeInformationProvider.value.uri.toString(), '/projects');
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful password sign-in opens its local destination', (
    tester,
  ) async {
    final account = _SuccessfulAccountClient();
    final router = _authRouter('/login?returnTo=/projects');
    addTearDown(router.dispose);
    await _pumpAuthRouter(tester, account, router);

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password-field')),
      'password',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(account.signInCalls, 1);
    expect(account.currentUserId, 'user-id');
    expect(router.routeInformationProvider.value.uri.toString(), '/projects');
  });

  testWidgets('password sign-in returns to the exact OAuth consent URI', (
    tester,
  ) async {
    final account = _SuccessfulAccountClient();
    final router = _authRouter(
      '/login?returnTo=%2Foauth%2Fconsent%3Fauthorization_id%3D'
      'a%252Fb%252Bc%252520d',
    );
    addTearDown(router.dispose);
    await _pumpAuthRouter(tester, account, router);

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password-field')),
      'password',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/oauth/consent?authorization_id=a%2Fb%2Bc%2520d',
    );
  });

  testWidgets('registration returns to the exact OAuth consent URI', (
    tester,
  ) async {
    final account = _SuccessfulAccountClient();
    final router = _authRouter(
      '/register?returnTo=%2Foauth%2Fconsent%3Fauthorization_id%3D'
      'a%252Fb%252Bc%252520d',
    );
    addTearDown(router.dispose);
    await _pumpAuthRouter(tester, account, router);

    await tester.enterText(
      find.byKey(const Key('register-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password-field')),
      'password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/oauth/consent?authorization_id=a%2Fb%2Bc%2520d',
    );
  });

  testWidgets('Apple sign-in failure is visible', (tester) async {
    await _pumpAuthScreen(
      tester,
      _FailingSocialAccountClient(),
      const LoginScreen(),
    );

    await tester.tap(find.text('Apple'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'Sign-in with Apple is unavailable right now. Try again or use another method.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Google sign-in failure is visible', (tester) async {
    await _pumpAuthScreen(
      tester,
      _FailingSocialAccountClient(),
      const LoginScreen(),
    );

    await tester.tap(find.text('Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'Sign-in with Google is unavailable right now. Try again or use another method.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('social sign-in is single-flight and can retry', (tester) async {
    final account = _PendingSocialAccountClient();
    await _pumpAuthScreen(tester, account, const LoginScreen());

    await tester.tap(find.text('Apple'));
    await tester.pump();
    await tester.tap(find.text('Apple'));
    await tester.pump();
    expect(account.appleCalls, 1);

    account.attempts.single.completeError(StateError('SECRET provider detail'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(account.appleCalls, 2);
  });

  testWidgets('social cancellation does not show an error', (tester) async {
    await _pumpAuthScreen(
      tester,
      _CancelledSocialAccountClient(),
      const LoginScreen(),
    );

    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('slow email sign-in stays single-flight and can be dismissed', (
    tester,
  ) async {
    final account = _PendingAccountClient();
    await _pumpAuthScreen(tester, account, const LoginScreen());

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password-field')),
      'password',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(account.signInCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));

    expect(find.byKey(const Key('account-auth-slow')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(account.signInCalls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Email sign in'), findsNothing);
    expect(account.signInCalls, 1);

    account.signIn.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'slow registration stays single-flight and accepts late success',
    (tester) async {
      final account = _PendingAccountClient();
      await _pumpAuthScreen(tester, account, const RegisterScreen());

      await tester.enterText(
        find.byKey(const Key('register-email-field')),
        'user@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('register-password-field')),
        'password',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-submit-button')));
      await tester.pump();

      expect(account.signUpCalls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));

      expect(find.byKey(const Key('register-auth-slow')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(account.signUpCalls, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('register-submit-button')),
            )
            .onPressed,
        isNull,
      );

      account.signUp.complete();
      await tester.pumpAndSettle();

      expect(find.text('Check your email'), findsOneWidget);
      expect(account.signUpCalls, 1);
    },
  );
}

Future<void> _pumpAuthScreen(
  WidgetTester tester,
  AccountClient account,
  Widget screen, {
  RuntimePublicConfig? config,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        accountAuthStateProvider.overrideWithValue(
          const AsyncData(AccountAuthState(signedIn: false)),
        ),
        accountOverviewProvider.overrideWith((ref) async => null),
        if (config != null)
          runtimePublicConfigProvider.overrideWithValue(config),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpAuthRouter(
  WidgetTester tester,
  AccountClient account,
  GoRouter router, {
  RuntimePublicConfig? config,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        accountAuthStateProvider.overrideWithValue(
          const AsyncData(AccountAuthState(signedIn: false)),
        ),
        if (config != null)
          runtimePublicConfigProvider.overrideWithValue(config),
      ],
      child: MaterialApp.router(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

GoRouter _authRouter(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, state) => LoginScreen(
          returnTo: state.uri.queryParameters['returnTo'] ?? '/today',
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (_, state) => RegisterScreen(
          returnTo: state.uri.queryParameters['returnTo'] ?? '/today',
        ),
      ),
      GoRoute(
        path: '/projects',
        builder: (_, _) => const Scaffold(body: Text('Projects')),
      ),
      GoRoute(
        path: '/oauth/consent',
        builder: (_, _) => const Scaffold(body: Text('OAuth consent')),
      ),
    ],
  );
}

class _SuccessfulAccountClient implements AccountClient {
  String? _userId;
  var signInCalls = 0;
  var signUpCalls = 0;
  String? signInCaptchaToken;
  String? signUpCaptchaToken;

  @override
  String? get currentUserId => _userId;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    signInCalls += 1;
    signInCaptchaToken = captchaToken;
    _userId = 'user-id';
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    String? redirectTo,
    String? captchaToken,
  }) async {
    signUpCalls += 1;
    signUpCaptchaToken = captchaToken;
    _userId = 'user-id';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingAccountClient implements AccountClient {
  final signIn = Completer<void>();
  final signUp = Completer<void>();
  var signInCalls = 0;
  var signUpCalls = 0;

  @override
  String? get currentUserId => null;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) {
    signInCalls += 1;
    return signIn.future;
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    String? redirectTo,
    String? captchaToken,
  }) {
    signUpCalls += 1;
    return signUp.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingSocialAccountClient implements AccountClient {
  @override
  String? get currentUserId => null;

  @override
  Future<void> signInWithApple({String? redirectTo}) {
    throw StateError('Apple unavailable');
  }

  @override
  Future<void> signInWithGoogle({String? redirectTo}) {
    throw StateError('Google unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnconfirmedEmailAccountClient implements AccountClient {
  @override
  String? get currentUserId => null;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) {
    throw const AuthApiException(
      'Email not confirmed',
      statusCode: '400',
      code: 'email_not_confirmed',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingEmailAccountClient implements AccountClient {
  _FailingEmailAccountClient(this.error);

  final Object error;

  @override
  String? get currentUserId => null;

  @override
  Future<void> signInWithEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) => Future<void>.error(error);

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) => Future<void>.error(error);

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    String? redirectTo,
    String? captchaToken,
  }) => Future<void>.error(error);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingSocialAccountClient implements AccountClient {
  final attempts = <Completer<void>>[];
  var appleCalls = 0;

  @override
  String? get currentUserId => null;

  @override
  Future<void> signInWithApple({String? redirectTo}) {
    appleCalls += 1;
    final attempt = Completer<void>();
    attempts.add(attempt);
    return attempt.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CancelledSocialAccountClient implements AccountClient {
  @override
  String? get currentUserId => null;

  @override
  Future<void> signInWithApple({String? redirectTo}) {
    return Future<void>.error(PlatformException(code: 'userCancelled'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
