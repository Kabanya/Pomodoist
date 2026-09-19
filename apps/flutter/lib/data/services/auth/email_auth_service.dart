import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/domain/models/account/email_auth.dart';

class EmailAuthController {
  EmailAuthController(this._auth, {String Function()? locale})
    : _locale = locale;

  final GoTrueClient? _auth;
  final String Function()? _locale;
  bool _busy = false;

  Future<EmailAuthResult?> submit({
    required EmailAuthAction action,
    required String email,
    String password = '',
    required String redirectTo,
    String? captchaToken,
  }) async {
    if (_busy) return null;
    final validation =
        validateAccountEmail(email) ??
        (action == EmailAuthAction.signIn || action == EmailAuthAction.signUp
            ? validateAccountPassword(password)
            : null);
    if (validation != null) throw validation;
    final auth = _auth;
    if (auth == null) {
      throw const AccountAuthFailure(
        AccountAuthFailureKind.serviceUnavailable,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.retry,
      );
    }
    _busy = true;
    try {
      final locale = _locale?.call();
      final localizedRedirect = localizedAccountAuthRedirect(
        redirectTo,
        locale,
      );
      final AuthResponse response;
      switch (action) {
        case EmailAuthAction.signIn:
          response = await auth.signInWithPassword(
            email: email.trim(),
            password: password,
            captchaToken: captchaToken,
          );
        case EmailAuthAction.signUp:
          response = await auth.signUp(
            email: email.trim(),
            password: password,
            emailRedirectTo: localizedRedirect,
            data: locale == null ? null : {'pomodoist_locale': locale},
            captchaToken: captchaToken,
          );
        case EmailAuthAction.magicLink:
          await auth.signInWithOtp(
            email: email.trim(),
            emailRedirectTo: localizedRedirect,
            shouldCreateUser: false,
            captchaToken: captchaToken,
          );
          return EmailAuthResult.checkEmail;
        case EmailAuthAction.resendConfirmation:
          await auth.resend(
            type: OtpType.signup,
            email: email.trim(),
            emailRedirectTo: localizedRedirect,
            captchaToken: captchaToken,
          );
          return EmailAuthResult.checkEmail;
      }
      if (response.session != null) return EmailAuthResult.signedIn;
      if (action == EmailAuthAction.signUp) {
        // Supabase masks existing accounts with an explicit empty identity list.
        if (response.user?.identities?.isEmpty == true) {
          throw const AccountAuthFailure(
            AccountAuthFailureKind.accountMayExist,
            field: AccountAuthField.email,
            recovery: AccountAuthRecovery.switchToSignIn,
          );
        }
        return EmailAuthResult.checkEmail;
      }
      throw const AccountAuthFailure(
        AccountAuthFailureKind.unexpected,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.retry,
      );
    } on AuthException catch (error) {
      // With create_user=false, GoTrue uses otp_disabled for an unknown address.
      if (error.code == 'otp_disabled' && action == EmailAuthAction.magicLink) {
        return EmailAuthResult.checkEmail;
      }
      if (error.code == 'user_not_found' &&
          (action == EmailAuthAction.magicLink ||
              action == EmailAuthAction.resendConfirmation)) {
        return EmailAuthResult.checkEmail;
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }
}
