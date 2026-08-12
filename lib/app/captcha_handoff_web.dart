import 'package:web/web.dart' as web;

void replaceWithCaptchaCallback(Uri uri) {
  web.window.location.replace(uri.toString());
}

void replaceWithOAuthRedirect(String url) {
  web.window.location.replace(url);
}
