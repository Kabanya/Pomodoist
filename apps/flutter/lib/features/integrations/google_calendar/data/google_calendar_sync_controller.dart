import 'package:app_account/app_account.dart';
import 'package:url_launcher/url_launcher.dart';

typedef GoogleCalendarFunctionInvoker =
    Future<AccountFunctionResponse> Function(Map<String, Object?> body);
typedef GoogleCalendarUrlLauncher = Future<bool> Function(Uri url);

class GoogleCalendarSyncController {
  GoogleCalendarSyncController({
    required GoogleCalendarFunctionInvoker invoke,
    GoogleCalendarUrlLauncher? openUrl,
  }) : _invoke = invoke,
       _openUrl =
           openUrl ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  final GoogleCalendarFunctionInvoker _invoke;
  final GoogleCalendarUrlLauncher _openUrl;

  Future<void> connect() async {
    final data = await _action('start');
    final rawUrl = data['authorizationUrl'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (url == null || url.scheme != 'https' || !await _openUrl(url)) {
      throw const GoogleCalendarServerException(
        'Could not open Google Calendar authorization.',
        code: 'authorization_unavailable',
      );
    }
  }

  Future<void> syncNow({bool interactive = false}) async {
    await _action('sync');
  }

  Future<void> disconnect() async {
    await _action('disconnect');
  }

  Future<Map<String, Object?>> _action(String action) async {
    final response = await _invoke({'action': action});
    final data = response.data is Map
        ? Map<String, Object?>.from(response.data! as Map)
        : const <String, Object?>{};
    if (response.status < 200 || response.status >= 300) {
      throw GoogleCalendarServerException(
        data['error'] is String
            ? data['error']! as String
            : 'Google Calendar request failed.',
        code: data['code'] is String
            ? data['code']! as String
            : response.status == 401
            ? 'auth_required'
            : 'service_unavailable',
      );
    }
    return data;
  }
}

class GoogleCalendarServerException implements Exception {
  const GoogleCalendarServerException(
    this.message, {
    this.code = 'service_unavailable',
  });

  final String code;

  final String message;

  @override
  String toString() => message;
}
