import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/localization/notification_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'each language survives preference reload, preserves auth callback and localizes channels',
    () async {
      for (final language in [
        AppLanguage.ptBR,
        AppLanguage.ja,
        AppLanguage.ko,
      ]) {
        SharedPreferences.setMockInitialValues({});
        final first = ProviderContainer();
        (await first.read(languageRepositoryProvider).setLanguage(language))
            .getOrThrow();
        first.dispose();
        final second = ProviderContainer();
        second.read(appLanguageProvider);
        await Future<void>.delayed(Duration.zero);
        expect(second.read(appLanguageProvider), language);
        second.dispose();
        final locale = language.locale!;
        final l10n = lookupAppLocalizations(locale);
        final notifications = NotificationScheduler(
          localizations: () => l10n.notificationCopy,
        );
        final details = notifications.localizedDetails(
          NotificationScheduler.taskStartDetails,
        );
        expect(details.android!.channelName, l10n.notificationTaskChannel);
        expect(
          details.android!.channelId,
          NotificationScheduler.taskStartDetails.android!.channelId,
        );
        final original = Uri.parse(
          'pomodoist://login-callback?returnTo=%2Foauth%2Fconsent%3Fclient_id%3Dx#nonce=keep',
        );
        final redirect = Uri.parse(
          localizedAccountAuthRedirect(
            original.toString(),
            locale.toLanguageTag(),
          ),
        );
        expect(redirect.scheme, original.scheme);
        expect(redirect.host, original.host);
        expect(redirect.query, original.query);
        expect(Uri.splitQueryString(redirect.fragment), {
          'nonce': 'keep',
          'lang': locale.toLanguageTag(),
        });
        final hint = const QuickAddParser().parse(
          l10n.quickAddHint,
          now: DateTime(2026, 9, 13),
        );
        expect(hint.schedule?.date, DateTime(2026, 9, 14));
        expect(hint.priority, 1);
        expect(hint.project, 'App');
        expect(hint.estimatedFocusIntervals, 4);
      }
    },
  );
  test(
    'Portuguese month names and CJK invalid times do not damage task text',
    () {
      const parser = QuickAddParser();
      final now = DateTime(2026, 1, 1);
      const months = [
        'janeiro',
        'fevereiro',
        'março',
        'abril',
        'maio',
        'junho',
        'julho',
        'agosto',
        'setembro',
        'outubro',
        'novembro',
        'dezembro',
      ];
      for (var index = 0; index < months.length; index++) {
        final parsed = parser.parse(
          'Reunião 15 de ${months[index]} às 3:30 da tarde',
          now: now,
        );
        expect(
          parsed.schedule?.start?.toLocal(),
          DateTime(2026, index + 1, 15, 15, 30),
          reason: months[index],
        );
        expect(parsed.content, 'Reunião');
      }
      for (final text in ['会議 午後13時', '회의 오후 13시', '会議 25時', '회의 25시']) {
        expect(parser.parse(text, now: now).content, text, reason: text);
      }
      expect(
        localizedAccountAuthRedirect('pomodoist://login-callback', 'ja\nwrong'),
        'pomodoist://login-callback',
      );
    },
  );
}
