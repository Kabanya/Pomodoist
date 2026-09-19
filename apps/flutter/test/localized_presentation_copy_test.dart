import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/ui/focus/widgets/focus_preset_localizations.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_repository_impl.dart';
import 'package:pomodoist/ui/productivity/widgets/achievement_localizations.dart';
import 'package:pomodoist/ui/settings/widgets/csv_task_import_card.dart';
import 'package:pomodoist/domain/models/tasks/csv_task_import.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'package:pomodoist/ui/tasks/widgets/task_search_palette.dart';
import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/ui/updates/widgets/update_copy.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';

void main() {
  test(
    'achievement titles stay distinct from descriptions in every locale',
    () {
      final achievements = evaluateAchievements(completions: [], intervals: []);
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        expect(achievements, hasLength(33));
        for (final item in achievements) {
          expect(item.titleFor(l10n), isNotEmpty);
          expect(item.subtitleFor(l10n), isNotEmpty);
          expect(item.titleFor(l10n), isNot(item.subtitleFor(l10n)));
          expect(item.titleFor(l10n), isNot(l10n.achievementTitle('unknown')));
        }
        final update = UpdateCopy(l10n);
        for (final phase in UpdatePhase.values) {
          expect(update.phase(phase), isNotEmpty);
        }
      }
      expect(
        achievements.first.titleFor(lookupAppLocalizations(const Locale('en'))),
        'First tomato',
      );
      expect(
        achievements.first.titleFor(lookupAppLocalizations(const Locale('ru'))),
        'Первый помидор',
      );
    },
  );

  test(
    'CSV errors localize at presentation and preserve row and input values',
    () {
      CsvTaskImportException? failure;
      try {
        CsvTaskImportDocument.parse(
          utf8.encode('content,custom-header\nTask,x'),
        );
      } on CsvTaskImportException catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      expect(failure!.issues.single.code, 'unknownHeader');
      expect(failure.issues.single.message, 'Unknown header "custom-header".');
      for (final locale in [
        const Locale('pt', 'BR'),
        const Locale('ja'),
        const Locale('ko'),
      ]) {
        final l10n = lookupAppLocalizations(locale);
        final formatted = formatCsvImportIssues(failure, l10n);
        expect(formatted, contains('custom-header'));
        expect(formatted, contains('1'));
        expect(formatted, isNot(contains('Unknown header')));
        expect(formatted, isNot(contains('Row')));
      }
    },
  );

  test(
    'Inbox displays and searches locally while user project names stay unchanged',
    () {
      final l10n = lookupAppLocalizations(const Locale('ja'));
      final inbox = _project(inboxProjectId, 'Inbox');
      expect(inbox.displayName(l10n), l10n.navInbox);
      expect(
        _project(inboxProjectId, 'My inbox').displayName(l10n),
        'My inbox',
      );
      expect(_project('user-project', 'Inbox').displayName(l10n), 'Inbox');
      expect(taskSearchPaletteResults([], [inbox], l10n.navInbox, l10n: l10n), [
        (id: 'project:$inboxProjectId', title: l10n.navInbox),
      ]);
      expect(taskSearchPaletteResults([], [inbox], 'Inbox', l10n: l10n), [
        (id: 'project:$inboxProjectId', title: l10n.navInbox),
      ]);
      expect(inbox.name, 'Inbox');
    },
  );

  test(
    'preset localization preserves renamed built-ins and user preset names',
    () {
      final l10n = lookupAppLocalizations(const Locale('ja'));
      expect(
        _preset(defaultPresetId, 'Classic').displayName(l10n),
        l10n.themeClassic,
      );
      expect(
        _preset(deepWorkPresetId, 'Deep Work').displayName(l10n),
        l10n.focusPresetDeepWork,
      );
      expect(
        _preset(shortSprintPresetId, 'Short Sprint').displayName(l10n),
        l10n.focusPresetShortSprint,
      );
      expect(
        _preset(defaultPresetId, 'My rhythm').displayName(l10n),
        'My rhythm',
      );
      expect(_preset('user-created', 'Classic').displayName(l10n), 'Classic');
    },
  );
}

FocusPresetItem _preset(String id, String name) => FocusPresetItem(
  id: id,
  userId: localUserId,
  name: name,
  workSeconds: 1500,
  shortBreakSeconds: 300,
  longBreakSeconds: 900,
  intervalsBeforeLongBreak: 4,
  autoStartBreaks: true,
  autoStartWork: false,
  allowPause: true,
  strictMode: false,
  isDefault: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

ProjectItem _project(String id, String name) => ProjectItem(
  id: id,
  userId: localUserId,
  name: name,
  orderKey: '0',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
