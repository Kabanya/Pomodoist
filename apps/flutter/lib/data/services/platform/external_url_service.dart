import 'package:url_launcher/url_launcher.dart';

final class ExternalUrlService {
  const ExternalUrlService();

  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
