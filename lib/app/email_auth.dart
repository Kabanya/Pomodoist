import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_auth_feedback.dart';
import 'account_providers.dart';

final emailAuthProvider = Provider<EmailAuthController>((ref) {
  final account = ref.watch(accountClientProvider);
  return EmailAuthController(
    account == null ? null : Supabase.instance.client.auth,
  );
});

enum EmailAuthAction { signIn, signUp, magicLink, resendConfirmation }

enum EmailAuthResult { signedIn, checkEmail }

class EmailAuthController {
  EmailAuthController(this._auth);

  final GoTrueClient? _auth;
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
            emailRedirectTo: redirectTo,
            captchaToken: captchaToken,
          );
        case EmailAuthAction.magicLink:
          await auth.signInWithOtp(
            email: email.trim(),
            emailRedirectTo: redirectTo,
            shouldCreateUser: false,
            captchaToken: captchaToken,
          );
          return EmailAuthResult.checkEmail;
        case EmailAuthAction.resendConfirmation:
          await auth.resend(
            type: OtpType.signup,
            email: email.trim(),
            emailRedirectTo: redirectTo,
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
