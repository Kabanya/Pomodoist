import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/config/app_language.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'locale tags, saved values and system preferences resolve consistently',
    () {
      for (final tag in ['pt', 'pt-BR', 'pt_PT', 'PT-br']) {
        expect(AppLanguage.fromLanguageTag(tag), AppLanguage.ptBR);
      }
      expect(AppLanguage.fromLanguageTag('ja-JP'), AppLanguage.ja);
      expect(AppLanguage.fromLanguageTag('ko-KR'), AppLanguage.ko);
      expect(AppLanguage.fromLanguageTag('ja<script>'), isNull);
      expect(AppLanguage.fromStorageValue('ptBR'), AppLanguage.ptBR);
      expect(AppLanguage.fromStorageValue('ru'), AppLanguage.ru);
      expect(
        resolveAppLocale(
          AppLanguage.system,
          systemLocales: [const Locale('xx'), const Locale('ko', 'KR')],
        ),
        const Locale('ko'),
      );
      expect(
        resolveAppLocale(AppLanguage.system, systemLocales: []),
        const Locale('en'),
      );
      expect(resolveAppLocale(AppLanguage.ptBR), const Locale('pt', 'BR'));
    },
  );

  const parser = QuickAddParser();
  final now = DateTime(2026, 9, 13, 10);
  test('Korean hours are durations, not a clock-time prefix', () {
    final result = parser.analyze('공부 오후 3시 2시간', now: now);
    expect(result.parsed.content, '공부');
    expect(result.parsed.schedule?.duration, const Duration(hours: 2));
    expect(result.matches.last.kind, QuickAddTokenKind.duration);
    expect(
      '공부 오후 3시 2시간'.substring(
        result.matches.last.start,
        result.matches.last.end,
      ),
      '2시간',
    );
  });
  test(
    'new languages parse schedules and highlight the original source spans',
    () {
      for (final input in [
        'Reunião 15 de setembro às 15:30 30 minutos',
        '会議9月15日午後3時30分30分',
        '회의9월 15일오후 3시 30분30분',
      ]) {
        final result = parser.analyze(input, now: now);
        expect(
          result.parsed.schedule?.start?.toLocal(),
          DateTime(2026, 9, 15, 15, 30),
          reason: input,
        );
        expect(
          result.parsed.schedule?.duration,
          const Duration(minutes: 30),
          reason: input,
        );
        expect(
          result.parsed.content,
          input.startsWith('Reunião')
              ? 'Reunião'
              : input.startsWith('会議')
              ? '会議'
              : '회의',
        );
        expect(
          result.matches.map((m) => m.kind),
          containsAll([
            QuickAddTokenKind.date,
            QuickAddTokenKind.time,
            QuickAddTokenKind.duration,
          ]),
          reason: input,
        );
        for (final span in result.matches) {
          expect(input.substring(span.start, span.end), isNotEmpty);
        }
      }
    },
  );
  test(
    'relative dates, meridiem, fullwidth digits and metadata retain their meaning',
    () {
      for (final input in [
        'Call amanhã às 12 da manhã',
        'Call 明日午前１２時',
        'Call 내일오전 12시',
      ]) {
        expect(
          parser.parse(input, now: now).schedule?.start?.toLocal(),
          DateTime(2026, 9, 14),
          reason: input,
        );
      }
      final result = parser.parse(
        '会議 明日午後12時 2時間 #"明日9月15日" @"30分" p1 3p',
        now: now,
      );
      expect(result.schedule?.start?.toLocal(), DateTime(2026, 9, 14, 12));
      expect(result.schedule?.duration, const Duration(hours: 2));
      expect(result.project, '明日9月15日');
      expect(result.labels, ['30分']);
      expect(result.priority, 1);
      expect(result.estimatedFocusIntervals, 3);
      expect(parser.parse('Call 2月30日午後3時', now: now).schedule, isNull);
      expect(parser.parse('Call 2월30일오후3시', now: now).schedule, isNull);
      expect(
        parser.parse('Call às 23:30-00:30', now: now).schedule?.duration,
        const Duration(hours: 1),
      );
    },
  );
}
