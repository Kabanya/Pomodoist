import 'package:url_launcher/url_launcher.dart';

const pomodoistPrivacyPolicyUrl = 'https://pomodoist.com/privacy/';
const pomodoistTermsOfUseUrl =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
const appleAccountUrl = 'https://account.apple.com/';

Future<bool> launchPomodoistExternalUrl(String url) {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
