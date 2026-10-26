import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/ai_quota_dependencies.dart';
import 'package:pomodoist/data/repositories/account/ai_quota_repository.dart';
import 'package:pomodoist/domain/models/account/ai_quota.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/settings/widgets/settings_ai_quota.dart';

import 'support/test_app.dart';

void main() {
  setUpAll(loadTestAppResources);

  Future<void> pump(WidgetTester tester, AiQuotaRepository? repository) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [aiQuotaRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: testAppBuilder,
            home: const Scaffold(
              body: SingleChildScrollView(child: SettingsAiQuota()),
            ),
          ),
        ),
      );

  testWidgets(
    'shows loading and then server usage, reset and shared quota explanation',
    (tester) async {
      final pending = Completer<AiQuota>();
      await pump(tester, _QuotaRepository(() => pending.future));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('requests used'), findsNothing);
      final reset = DateTime(2026, 11, 1, 12);
      pending.complete(AiQuota(used: 137, limit: 250, resetsAt: reset));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.textContaining('137 of 250 requests used · 113 remaining'),
        findsOneWidget,
      );
      expect(find.textContaining('Resets Nov 1, 2026'), findsOneWidget);
      expect(
        find.textContaining(
          'Task analysis and new automatic categories share this monthly limit.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Cached categories and manual corrections are free.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('error offers retry without claiming a quota', (tester) async {
    var calls = 0;
    await pump(
      tester,
      _QuotaRepository(() async {
        if (++calls == 1) throw StateError('offline');
        return AiQuota(used: 2, limit: 9, resetsAt: DateTime.utc(2026, 11));
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load the AI limit.'), findsOneWidget);
    expect(find.textContaining('requests used'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.textContaining('2 of 9 requests used · 7 remaining'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed out hides the quota', (tester) async {
    await pump(tester, null);
    await tester.pumpAndSettle();
    expect(find.text('AI usage'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}

class _QuotaRepository implements AiQuotaRepository {
  _QuotaRepository(this.onLoad);
  final Future<AiQuota> Function() onLoad;
  @override
  Future<AiQuota> load() => onLoad();
}
