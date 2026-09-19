import 'package:pomodoist/domain/models/account/email_auth.dart';
import 'package:pomodoist/data/services/auth/email_auth_service.dart';
import 'package:app_account/app_account.dart';

/// UI tests control the auth boundary; email_auth_test covers the GoTrue adapter.
class AccountEmailAuth extends EmailAuthController {
  AccountEmailAuth(this.account) : super(null);
  final AccountClient account;

  @override
  Future<EmailAuthResult?> submit({
    required EmailAuthAction action,
    required String email,
    String password = '',
    required String redirectTo,
    String? captchaToken,
  }) async {
    switch (action) {
      case EmailAuthAction.signIn:
        await account.signInWithPassword(
          email: email.trim(),
          password: password,
          captchaToken: captchaToken,
        );
        return EmailAuthResult.signedIn;
      case EmailAuthAction.signUp:
        await account.signUpWithPassword(
          email: email.trim(),
          password: password,
          redirectTo: redirectTo,
          captchaToken: captchaToken,
        );
        return account.currentUserId == null
            ? EmailAuthResult.checkEmail
            : EmailAuthResult.signedIn;
      case EmailAuthAction.magicLink:
      case EmailAuthAction.resendConfirmation:
        await account.signInWithEmail(
          email.trim(),
          redirectTo: redirectTo,
          captchaToken: captchaToken,
        );
        return EmailAuthResult.checkEmail;
    }
  }
}
