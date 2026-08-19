import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_auth_feedback.dart';
import 'package:pomodoist/app/captcha_security.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:pomodoist/l10n/app_localizations_ar.dart';
import 'package:pomodoist/l10n/app_localizations_de.dart';
import 'package:pomodoist/l10n/app_localizations_en.dart';
import 'package:pomodoist/l10n/app_localizations_es.dart';
import 'package:pomodoist/l10n/app_localizations_fr.dart';
import 'package:pomodoist/l10n/app_localizations_ru.dart';
import 'package:pomodoist/l10n/app_localizations_zh.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('validates required fields without sending them to the server', () {
    expect(
      validateAccountEmail('')?.kind,
      AccountAuthFailureKind.emailRequired,
    );
    expect(
      validateAccountEmail('not-an-email')?.kind,
      AccountAuthFailureKind.emailInvalid,
    );
    expect(validateAccountEmail(' person+tag@example.com '), isNull);
    expect(
      validateAccountPassword('')?.kind,
      AccountAuthFailureKind.passwordRequired,
    );
    expect(validateAccountPassword('anything'), isNull);
  });

  for (final entry in <String, AccountAuthFailureKind>{
    'invalid_credentials': AccountAuthFailureKind.invalidCredentials,
    'user_not_found': AccountAuthFailureKind.invalidCredentials,
    'email_not_confirmed': AccountAuthFailureKind.emailUnconfirmed,
    'weak_password': AccountAuthFailureKind.weakPassword,
    'email_exists': AccountAuthFailureKind.accountMayExist,
    'user_already_exists': AccountAuthFailureKind.accountMayExist,
    'over_request_rate_limit': AccountAuthFailureKind.rateLimited,
    'over_email_send_rate_limit': AccountAuthFailureKind.emailRateLimited,
    'captcha_failed': AccountAuthFailureKind.captchaFailed,
    'request_timeout': AccountAuthFailureKind.timeout,
    'signup_disabled': AccountAuthFailureKind.signUpDisabled,
    'provider_disabled': AccountAuthFailureKind.providerUnavailable,
    'user_banned': AccountAuthFailureKind.accountRestricted,
    'otp_expired': AccountAuthFailureKind.linkExpired,
  }.entries) {
    test('maps ${entry.key} to ${entry.value.name}', () {
      final failure = classifyAccountAuthFailure(
        AuthApiException('server detail', code: entry.key),
        operation: AccountAuthOperation.signUp,
      );
      expect(failure.kind, entry.value);
    });
  }

  test('distinguishes offline, service, timeout, and cancellation', () {
    expect(
      classifyAccountAuthFailure(
        AuthRetryableFetchException(message: 'socket detail'),
        operation: AccountAuthOperation.passwordSignIn,
      ).kind,
      AccountAuthFailureKind.offline,
    );
    expect(
      classifyAccountAuthFailure(
        AuthRetryableFetchException(
          message: 'server detail',
          statusCode: '503',
        ),
        operation: AccountAuthOperation.passwordSignIn,
      ).kind,
      AccountAuthFailureKind.serviceUnavailable,
    );
    expect(
      classifyAccountAuthFailure(
        TimeoutException('secret detail'),
        operation: AccountAuthOperation.bootstrap,
      ).kind,
      AccountAuthFailureKind.timeout,
    );
    expect(
      classifyAccountAuthFailure(
        PlatformException(code: 'userCancelled'),
        operation: AccountAuthOperation.apple,
      ).isCancelled,
      isTrue,
    );
  });

  test('uses status-only compatibility without inspecting server messages', () {
    expect(
      classifyAccountAuthFailure(
        const AuthApiException('arbitrary detail', statusCode: '400'),
        operation: AccountAuthOperation.passwordSignIn,
      ).kind,
      AccountAuthFailureKind.invalidCredentials,
    );
    expect(
      classifyAccountAuthFailure(
        const AuthApiException('arbitrary detail', statusCode: '429'),
        operation: AccountAuthOperation.magicLink,
      ).kind,
      AccountAuthFailureKind.emailRateLimited,
    );
    expect(
      classifyAccountAuthFailure(
        const AuthApiException('arbitrary detail', statusCode: '503'),
        operation: AccountAuthOperation.signUp,
      ).kind,
      AccountAuthFailureKind.serviceUnavailable,
    );
  });

  for (final code in NativeCaptchaFailureCode.values) {
    test('maps native CAPTCHA ${code.name}', () {
      final failure = classifyAccountAuthFailure(
        NativeCaptchaException(code),
        operation: AccountAuthOperation.captcha,
      );
      expect(failure.field, AccountAuthField.captcha);
      expect(failure.recovery, AccountAuthRecovery.retryCaptcha);
    });
  }

  test('never presents raw server details in any supported locale', () {
    const secret = 'SECRET-user@example.com-token';
    final failure = classifyAccountAuthFailure(
      const AuthApiException(secret, code: 'unexpected_failure'),
      operation: AccountAuthOperation.passwordSignIn,
    );
    final localizations = <AppLocalizations>[
      AppLocalizationsAr(),
      AppLocalizationsDe(),
      AppLocalizationsEn(),
      AppLocalizationsEs(),
      AppLocalizationsFr(),
      AppLocalizationsRu(),
      AppLocalizationsZh(),
    ];
    for (final l10n in localizations) {
      final feedback = presentAccountAuthFailure(
        l10n,
        failure,
        operation: AccountAuthOperation.passwordSignIn,
      );
      expect(feedback.message, isNotEmpty);
      expect(feedback.message, isNot(contains(secret)));
      expect(feedback.message, isNot(contains('AuthApiException')));
    }
  });

  test('sanitizes callback errors to an allow-listed category', () {
    final uri = Uri.parse(
      'pomodoist://login-callback?error_code=otp_expired'
      '&error_description=SECRET_DESCRIPTION&token=SECRET_TOKEN',
    );
    final value = safeAccountAuthCallbackFailureValue(uri);

    expect(value, AccountAuthFailureKind.linkExpired.name);
    expect(value, isNot(contains('SECRET')));
    expect(
      accountAuthCallbackFailureFromValue(value)?.recovery,
      AccountAuthRecovery.sendNewLink,
    );
    expect(accountAuthCallbackFailureFromValue('invalid_credentials'), isNull);
  });

  test('treats an OAuth access denial as a quiet cancellation', () {
    final value = safeAccountAuthCallbackFailureValue(
      Uri.parse('pomodoist://login-callback?error=access_denied'),
    );
    expect(accountAuthCallbackFailureFromValue(value)?.isCancelled, isTrue);
  });
}
