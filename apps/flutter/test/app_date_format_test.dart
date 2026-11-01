import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/domain/models/settings/app_date_format.dart';
import 'package:pomodoist/ui/core/localization/app_date_formatter.dart';
import 'package:pomodoist/ui/core/localization/app_localizations_en.dart';
import 'package:pomodoist/ui/core/localization/app_localizations_ru.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/ui/core/view_models/app_date_format_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  Future<AppDateFormatter> formatter(
    AppDateFormat mode,
    String language,
  ) async => AppDateFormatter(
    mode,
    await GlobalMaterialLocalizations.delegate.load(
      language == 'pt_BR' ? const Locale('pt', 'BR') : Locale(language),
    ),
    language,
  );

  test('automatic preserves each caller format and localized input', () async {
    for (final locale in ['en', 'ru']) {
      final f = await formatter(AppDateFormat.automatic, locale);
      final day = DateTime(2026, 11, 2);
      expect(f.format(day), f.material.formatCompactDate(day));
      expect(
        f.format(day, automatic: () => 'existing label'),
        'existing label',
      );
      expect(f.parse(f.format(day)), day);
      expect(f.inputHint, f.material.dateHelpText);
    }
  });

  test(
    'explicit numeric formats keep their order independently of language',
    () async {
      for (final locale in ['en', 'ru']) {
        for (final (mode, text) in [
          (AppDateFormat.dayMonthYear, '02.11.2026'),
          (AppDateFormat.monthDayYear, '11/02/2026'),
          (AppDateFormat.yearMonthDay, '2026-11-02'),
        ]) {
          final f = await formatter(mode, locale);
          expect(f.format(DateTime(2026, 11, 2)), text);
          expect(f.parse(text), DateTime(2026, 11, 2));
          expect(
            f.parse('02/11/2026'),
            mode == AppDateFormat.monthDayYear ? DateTime(2026, 2, 11) : isNull,
          );
        }
      }
    },
  );

  test('all supported long dates round trip including leap days', () async {
    for (final locale in [
      'en',
      'ru',
      'de',
      'es',
      'fr',
      'ar',
      'zh',
      'pt',
      'pt_BR',
      'ja',
      'ko',
    ]) {
      final f = await formatter(AppDateFormat.longDate, locale);
      for (final date in [DateTime(2026, 11, 2), DateTime(2024, 2, 29)]) {
        expect(
          f.parse(f.format(date)),
          date,
          reason: '$locale ${f.format(date)}',
        );
      }
    }
  });

  test(
    'explicit input rejects invalid, incomplete and trailing text',
    () async {
      final f = await formatter(AppDateFormat.dayMonthYear, 'en');
      for (final text in [
        '',
        'unfinished',
        '30.02.2024',
        '29.02.2025',
        '01.13.2026',
        '02.11.2026 extra',
      ]) {
        expect(f.parse(text), isNull, reason: text);
      }
      expect(f.parse(' 29.02.2024 '), DateTime(2024, 2, 29));
    },
  );

  test(
    'picker enforces bounds in every format without changing the date order',
    () async {
      for (final mode in AppDateFormat.values) {
        final f = await formatter(mode, 'en');
        DateTime? parse(String text) => parsePickerDate(
          text,
          f.material,
          firstDate: DateTime(2024, 2, 1, 12),
          lastDate: DateTime(2024, 2, 29, 12),
          formatter: f,
        );
        expect(parse(f.format(DateTime(2024, 2, 1))), DateTime(2024, 2, 1));
        expect(parse(f.format(DateTime(2024, 2, 29))), DateTime(2024, 2, 29));
        expect(parse(f.format(DateTime(2024, 1, 31))), isNull);
        expect(parse(f.format(DateTime(2024, 3, 1))), isNull);
        expect(parse(''), isNull);
      }
    },
  );

  test(
    'relative labels survive every preference and automatic keeps month names',
    () async {
      final now = DateTime(2026, 11, 2, 12);
      for (final (language, l10n) in [
        ('en', AppLocalizationsEn()),
        ('ru', AppLocalizationsRu()),
      ]) {
        for (final mode in AppDateFormat.values) {
          final f = await formatter(mode, language);
          expect(
            f.formatTaskListDate(DateTime(2026, 11, 1), l10n, now: now),
            l10n.yesterday,
          );
          expect(
            f.formatTaskListDate(DateTime(2026, 11, 2), l10n, now: now),
            l10n.today,
          );
          expect(
            f.formatTaskListDate(DateTime(2026, 11, 3), l10n, now: now),
            l10n.tomorrow,
          );
          expect(
            f.formatTaskListDate(DateTime(2026, 11, 5), l10n, now: now),
            mode == AppDateFormat.automatic
                ? (language == 'en' ? 'November 5' : '5 ноября')
                : f.format(DateTime(2026, 11, 5)),
          );
        }
      }
    },
  );

  test(
    'time, overnight dates and recurrence survive explicit formatting',
    () async {
      final f = await formatter(AppDateFormat.yearMonthDay, 'ru');
      final start = DateTime(2026, 11, 2, 16, 42);
      expect(
        f.formatWithTime(start, automatic: () => 'unused'),
        '2026-11-02 16:42',
      );
      final rows = taskListScheduleRows(
        TaskSchedule.timed(start: start, end: DateTime(2026, 11, 3, 17, 42)),
        formatDate: f.format,
        formatTime: (day) => '${day.hour}:${day.minute}',
        recurrenceLabel: 'Every 2 days',
        displayMode: TaskTimeDisplayMode.range,
      );
      expect(rows, [
        ['2026-11-02', '16:42'],
        ['2026-11-03', '17:42'],
        ['Every 2 days'],
      ]);
      final automatic = await formatter(AppDateFormat.automatic, 'ru');
      expect(
        automatic.formatWithTime(start, automatic: () => 'existing timestamp'),
        'existing timestamp',
      );
    },
  );

  test(
    'choice persists and reloads, unknown stored values use automatic',
    () async {
      final repository = _Preferences();
      final first = ProviderContainer(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(first.dispose);
      final controller = first.read(appDateFormatProvider.notifier);
      await controller.ready;
      expect(first.read(appDateFormatProvider), AppDateFormat.automatic);
      await controller.setFormat(AppDateFormat.yearMonthDay);
      expect(repository.values[appDateFormatPreferenceKey], 'yearMonthDay');
      final restored = ProviderContainer(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(restored.dispose);
      await restored.read(appDateFormatProvider.notifier).ready;
      expect(restored.read(appDateFormatProvider), AppDateFormat.yearMonthDay);
      for (final invalid in ['future-format', 123]) {
        repository.values[appDateFormatPreferenceKey] = invalid;
        final other = ProviderContainer(
          overrides: [
            preferencesRepositoryProvider.overrideWithValue(repository),
          ],
        );
        await other.read(appDateFormatProvider.notifier).ready;
        expect(other.read(appDateFormatProvider), AppDateFormat.automatic);
        other.dispose();
      }
    },
  );

  test(
    'late hydration cannot overwrite a new selection; write failures are reported',
    () async {
      final repository = _Preferences()
        ..pendingRead = Completer<Result<Map<String, Object>>>();
      final container = ProviderContainer(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appDateFormatProvider.notifier);
      await controller.setFormat(AppDateFormat.dayMonthYear);
      repository.pendingRead!.complete(
        const Result.ok({appDateFormatPreferenceKey: 'longDate'}),
      );
      await controller.ready;
      expect(container.read(appDateFormatProvider), AppDateFormat.dayMonthYear);
      repository.failWrites = true;
      await expectLater(
        controller.setFormat(AppDateFormat.longDate),
        throwsStateError,
      );
      expect(container.read(appDateFormatProvider), AppDateFormat.dayMonthYear);
      repository.failWrites = false;
      await controller.setFormat(AppDateFormat.monthDayYear);
      expect(container.read(appDateFormatProvider), AppDateFormat.monthDayYear);
    },
  );

  test(
    'failed choice before hydration still restores the saved format',
    () async {
      final repository = _Preferences()
        ..pendingRead = Completer<Result<Map<String, Object>>>()
        ..failWrites = true;
      final container = ProviderContainer(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appDateFormatProvider.notifier);
      await expectLater(
        controller.setFormat(AppDateFormat.longDate),
        throwsStateError,
      );
      repository.pendingRead!.complete(
        const Result.ok({appDateFormatPreferenceKey: 'dayMonthYear'}),
      );
      await controller.ready;
      expect(container.read(appDateFormatProvider), AppDateFormat.dayMonthYear);
    },
  );

  test(
    'rapid choices are written in order and a failed load leaves automatic',
    () async {
      final repository = _Preferences()..pendingWrite = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appDateFormatProvider.notifier);
      await controller.ready;
      final first = controller.setFormat(AppDateFormat.dayMonthYear);
      final last = controller.setFormat(AppDateFormat.longDate);
      repository.pendingWrite!.complete();
      await Future.wait([first, last]);
      expect(container.read(appDateFormatProvider), AppDateFormat.longDate);
      expect(repository.values[appDateFormatPreferenceKey], 'longDate');

      final failing = _Preferences()
        ..pendingRead = Completer<Result<Map<String, Object>>>();
      final other = ProviderContainer(
        overrides: [preferencesRepositoryProvider.overrideWithValue(failing)],
      );
      addTearDown(other.dispose);
      final loading = other.read(appDateFormatProvider.notifier).ready;
      failing.pendingRead!.complete(
        Result.error(StateError('Read unavailable'), StackTrace.current),
      );
      await loading;
      expect(other.read(appDateFormatProvider), AppDateFormat.automatic);
      await other
          .read(appDateFormatProvider.notifier)
          .setFormat(AppDateFormat.yearMonthDay);
      expect(other.read(appDateFormatProvider), AppDateFormat.yearMonthDay);
    },
  );
}

class _Preferences implements PreferencesRepository {
  final values = <String, Object>{};
  Completer<Result<Map<String, Object>>>? pendingRead;
  Completer<void>? pendingWrite;
  bool failWrites = false;

  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) async =>
      pendingRead == null ? Result.ok({...values}) : pendingRead!.future;

  @override
  Future<Result<void>> write(Map<String, Object?> updates) =>
      Result.capture(() async {
        await pendingWrite?.future;
        if (failWrites) throw StateError('Storage unavailable');
        for (final entry in updates.entries) {
          if (entry.value == null) {
            values.remove(entry.key);
          } else {
            values[entry.key] = entry.value!;
          }
        }
      });
}
