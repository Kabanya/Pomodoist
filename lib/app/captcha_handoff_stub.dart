void replaceWithCaptchaCallback(Uri uri) {
  throw UnsupportedError('CAPTCHA handoff is only available on the web');
}

void replaceWithOAuthRedirect(String url) {
  throw UnsupportedError('OAuth handoff is only available on the web');
}
